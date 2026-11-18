require_relative "test_helper"

class ModelBoundariesTest < Minitest::Test
  self.unpinned_rollback_tests = %w[
    test_models_and_bulk_sql_share_visibility_and_rollback
    test_bulk_appointment_locks_are_held_until_transaction_end
  ]
  self.committed_demo_tests = %w[test_daily_batch_rolls_back_its_marker_and_deliveries_then_can_retry]

  AUSTIN_CLINIC_ID = 1
  PHOENIX_CLINIC_ID = 5
  ADULT_PATIENT_ID = 111
  CHILD_PATIENT_ID = 161
  CHILD_APPOINTMENT_ID = 22
  AUTHORIZED_GUARANTOR_ID = 190
  OTHER_GUARANTOR_ID = 191
  UNLINKED_APPOINTMENT_ID = 990991
  MISSING_PATIENT_ID = 990991

  class FailOnSecondDelivery < ReminderFlow::FakeSender
    attr_reader :attempts

    def initialize
      @attempts = 0
    end

    def deliver(**message)
      @attempts += 1
      raise "Simulated mid-batch failure" if @attempts == 2

      super
    end
  end

  def setup
    restore_demo_fixture
  end

  def with_rollback
    Database.open do |db|
      db.transaction do
        yield db
        raise ActiveRecord::Rollback
      end
    end
  end

  def test_board_countdown_uses_earliest_open_unanswered_visit_in_clinic_timezone
    Database.open do |_db|
      entry = FollowUpCase.new(patient: Patient.first, state: "attention")
      setting = ClinicSetting.find_by!(clinic_id: AUSTIN_CLINIC_ID)
      build_visit = ->(hour) { Visit.new(start_at: Time.utc(2026, 11, 6, hour), clinic_setting: setting) }
      entry.issues.build(code: "contact", visit: build_visit.call(8))
      entry.issues.build(code: "no_response", visit: build_visit.call(12))
      unanswered = entry.issues.build(code: "no_response", visit: build_visit.call(10))
      entry.issues.build(code: "no_response", visit: build_visit.call(9), resolved_at: Time.current)
      result = BoardCaseSerializer.new(entry, resolution: nil, latest: nil).as_json
      assert_equal "2026-11-06T16:00:00Z", build_visit.call(10).starts_at_utc.iso8601
      assert_equal true, result.fetch("no_response")
      assert_equal false, result.fetch("delivery_failed")
      assert_equal "2026-11-06T16:00:00Z", result.fetch("no_response_start_at")
      assert_equal result.fetch("no_response_start_at"),
        FollowUpIssueSerializer.new(unanswered, visible: true).as_json.fetch("start_at_utc")
      entry.issues.each { |issue| issue.resolved_at = Time.current }
      resolved = BoardCaseSerializer.new(entry, resolution: nil, latest: nil).as_json
      assert_nil resolved.fetch("no_response_start_at")
      assert_equal false, resolved.fetch("no_response")
      assert_equal false, resolved.fetch("reminders_blocked")
    end
  end

  def test_runtime_and_provisioning_connections_have_explicit_types
    Database.open { |connection| assert_instance_of Database::Session, connection }
    Database.provision(ENV.fetch("APP_ADMIN_URL")) do |connection|
      assert_instance_of PG::Connection, connection
    end
  end

  def test_models_and_bulk_sql_share_visibility_and_rollback
    Database.open do |db|
      assert_raises(RuntimeError) do
        db.transaction do
          visit = Visit.create!(
            appointment_id: UNLINKED_APPOINTMENT_ID, patient_id: ADULT_PATIENT_ID,
            clinic_id: AUSTIN_CLINIC_ID, revision: "transaction-test",
            start_at: Time.utc(2026, 11, 8, 12)
          )
          visible_id = db.exec_params(
            "SELECT id FROM desk.visits WHERE appointment_id=$1", [UNLINKED_APPOINTMENT_ID]
          ).first.fetch("id")
          assert_equal visit.id, visible_id

          db.exec_params(
            "UPDATE desk.visits SET confirmed_by=$1 WHERE id=$2", ["Transaction test", visit.id]
          )
          assert_equal "Transaction test", visit.reload.confirmed_by
          raise "Roll back model and SQL changes together"
        end
      end

      refute Visit.exists?(appointment_id: UNLINKED_APPOINTMENT_ID)
      remaining = db.exec_params(
        "SELECT id FROM desk.visits WHERE appointment_id=$1", [UNLINKED_APPOINTMENT_ID]
      )
      assert_equal 0, remaining.ntuples
    end
  end

  def test_cached_pms_models_are_read_only
    Database.open do |_db|
      appointment = Appointment.find(102)
      assert_raises(ActiveRecord::ReadOnlyRecord) { appointment.update!(status: "broken") }
      assert_equal "scheduled", appointment.reload.status
    end
  end

  def test_reminders_support_bigint_clinic_and_appointment_ids
    with_rollback do |db|
      clinic_id = 3_000_000_000
      Clinic.insert_all!([{ id: clinic_id, name: "Large source identifier" }])
      ClinicSetting.create!(clinic_id: clinic_id, timezone: "America/Chicago", sender: "+15125550197")
      ContactPermission.create!(patient_id: ADULT_PATIENT_ID, clinic_id: clinic_id, sms: true, email: true)
      Appointment.insert_all!([{
        id: clinic_id, patient_id: ADULT_PATIENT_ID, clinic_id: clinic_id,
        start_at: Time.utc(2026, 11, 12, 12), status: "scheduled"
      }])

      assert_equal 1, ReminderFlow.new.run(clinic_id)
      assert_equal clinic_id, Message.where(clinic_id: clinic_id).sole.clinic_id
      assert_equal 0, ReminderFlow.new.run(clinic_id)
    end
  end

  def test_reconciliation_selects_schedule_changes_but_ignores_routine_edits
    with_rollback do |db|
      flow = ReminderFlow.new
      ReconcileAppointments.new(now: flow.now).for_clinic(AUSTIN_CLINIC_ID)
      existing_phoenix_ids = Appointment.needing_reconciliation(PHOENIX_CLINIC_ID, now: TEST_NOW).map(&:id)

      moved_clinic = Appointment.find(102)
      moved_time = Appointment.find(103)
      canceled = Appointment.find(106)
      changed_patient = Appointment.find(107)
      routine_provider_edit = Appointment.find(123)
      routine_duration_edit = Appointment.find(110)

      Appointment.where(id: moved_clinic.id).update_all(clinic_id: PHOENIX_CLINIC_ID)
      Appointment.where(id: moved_time.id).update_all(start_at: moved_time.start_at + 1.hour)
      Appointment.where(id: canceled.id).update_all(status: "unscheduled")
      Appointment.where(id: changed_patient.id).update_all(patient_id: ADULT_PATIENT_ID)
      Appointment.where(id: routine_provider_edit.id).update_all(provider_name: "Routine edit")
      Appointment.where(id: routine_duration_edit.id).update_all(length_minutes: 45)

      expected_austin = [moved_clinic.id, moved_time.id, canceled.id, changed_patient.id].sort
      austin = Appointment.needing_reconciliation(AUSTIN_CLINIC_ID, now: TEST_NOW)
      phoenix = Appointment.needing_reconciliation(PHOENIX_CLINIC_ID, now: TEST_NOW)
      assert_equal expected_austin, austin.map(&:id)
      assert_equal (existing_phoenix_ids + [moved_clinic.id]).sort, phoenix.map(&:id).sort
    end
  end

  def test_bulk_appointment_locks_are_held_until_transaction_end
    ids = [3_000_000_000, 992101]
    try_locks = lambda do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          connection.transaction do
            ids.map do |id|
              key = id % Database::LOCK_KEY_MODULUS
              connection.select_value("SELECT pg_try_advisory_xact_lock(#{Database::APPOINTMENT_LOCK_NAMESPACE},#{key})")
            end
          end
        end
      end.value
    end

    ApplicationRecord.transaction do
      Database.lock_appointments(ids.reverse + ids)
      assert_equal [false, false], try_locks.call
    end
    assert_equal [true, true], try_locks.call
  end

  def test_reconciliation_validates_and_inserts_new_visits_in_batches
    with_rollback do |_db|
      ids = (992001..992020).to_a
      Appointment.insert_all!(ids.map do |id|
        { id: id, patient_id: ADULT_PATIENT_ID, clinic_id: AUSTIN_CLINIC_ID,
          start_at: Time.utc(2026, 11, 12, 12), status: "scheduled" }
      end)
      queries = []
      listener = ->(*arguments) { queries << arguments.last[:sql] unless arguments.last[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
        ReconcileAppointments.new(now: TEST_NOW).for_clinic(AUSTIN_CLINIC_ID)
      end

      visits = Visit.current.where(appointment_id: ids)
      assert_equal ids, visits.order(:appointment_id).pluck(:appointment_id)
      assert_equal [ADULT_PATIENT_ID], visits.distinct.pluck(:patient_id)
      assert_equal [AUSTIN_CLINIC_ID], visits.distinct.pluck(:clinic_id)
      assert_equal [Appointment.find(ids.first).confirmation_revision], visits.where(appointment_id: ids.first).pluck(:revision)
      assert_operator queries.length, :<=, 14, "Visit creation and history maintenance should use bounded batches."
      ReconcileAppointments.new(now: TEST_NOW).for_clinic(AUSTIN_CLINIC_ID)
      assert_equal ids.length, Visit.current.where(appointment_id: ids).count
    end
  end

  def test_bulk_reconciliation_preserves_required_clinic_setting_validation
    with_rollback do |_db|
      clinic_id = 992100
      Clinic.insert_all!([{ id: clinic_id, name: "Unconfigured clinic" }])
      Appointment.insert_all!([{
        id: clinic_id, patient_id: ADULT_PATIENT_ID, clinic_id: clinic_id,
        start_at: Time.utc(2026, 11, 12, 12), status: "scheduled"
      }])

      assert_raises(ActiveRecord::RecordInvalid) do
        ReconcileAppointments.new(now: TEST_NOW).for_clinic(clinic_id)
      end
      refute Visit.exists?(appointment_id: clinic_id)
    end
  end

  def test_visit_loading_scopes_permissions_and_guarantor_matching
    with_rollback do |db|
      flow = ReminderFlow.new
      ReconcileAppointments.new(now: flow.now).for_clinic(AUSTIN_CLINIC_ID)
      child_visit = Visit.current.find_by!(appointment_id: CHILD_APPOINTMENT_ID)
      loaded_visit = flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id]).sole
      contact = flow.contact_policy.for_visit(loaded_visit)

      assert_equal CHILD_PATIENT_ID, loaded_visit.patient_id
      assert_equal AUTHORIZED_GUARANTOR_ID, contact.id
      assert_equal "Demo Patient #{AUTHORIZED_GUARANTOR_ID}", contact.name
      assert_equal "(512) 555-0100", loaded_visit.clinic.phone
      assert_empty flow.load_visits(PHOENIX_CLINIC_ID, ids: [child_visit.id])
      assert_empty flow.load_visits(AUSTIN_CLINIC_ID, ids: [])
      assert_empty flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id], patient_id: ADULT_PATIENT_ID)
      empty_window = child_visit.start_at.to_date...child_visit.start_at.to_date
      assert_empty flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id], days: empty_window)

      permission = ContactPermission.where(patient_id: CHILD_PATIENT_ID, clinic_id: AUSTIN_CLINIC_ID)
      permission.update_all(authorized_guarantor_id: OTHER_GUARANTOR_ID)
      assert_nil flow.contact_policy.for_visit(flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id]).sole)
      permission.update_all(authorized_guarantor_id: CHILD_PATIENT_ID)
      assert_nil flow.contact_policy.for_visit(flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id]).sole)

      permission.delete_all
      without_permission = flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id]).sole
      refute without_permission.sms_permitted?
      refute without_permission.email_permitted?
      assert_nil flow.contact_policy.for_visit(without_permission)

      child_visit.update!(current: false)
      assert_empty flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id])
      historical = flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id], current: false).sole
      assert_equal child_visit.id, historical.id
      Appointment.where(id: child_visit.appointment_id).update_all(start_at: child_visit.start_at + 1.hour)
      changed_source = flow.load_visits(AUSTIN_CLINIC_ID, ids: [child_visit.id], current: false).sole
      assert_nil changed_source.provider_name
    end
  end

  def test_missing_patient_cannot_supply_a_recipient_or_permissions
    with_rollback do |db|
      Visit.insert_all!([{
        appointment_id: UNLINKED_APPOINTMENT_ID, patient_id: MISSING_PATIENT_ID,
        clinic_id: AUSTIN_CLINIC_ID, revision: "missing-patient", start_at: TEST_NOW
      }])
      flow = ReminderFlow.new
      visit = flow.load_visits(AUSTIN_CLINIC_ID, patient_id: MISSING_PATIENT_ID).sole

      assert_nil visit.patient
      assert_equal "Patient mapping needs review", visit.patient_name
      refute visit.sms_permitted?
      refute visit.email_permitted?
      assert_nil flow.contact_policy.for_visit(visit)
    end
  end

  def test_visit_context_is_loaded_in_batches_instead_of_per_visit
    Database.open do |db|
      queries = []
      listener = lambda do |*arguments|
        payload = arguments.last
        queries << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA"
      end
      flow = ReminderFlow.new

      ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
        visits = flow.load_visits(AUSTIN_CLINIC_ID, current: false)
        assert_operator visits.length, :>, 30
        visits.each do |visit|
          visit.patient_name
          visit.provider_name
          visit.sms_permitted?
          visit.email_permitted?
          flow.contact_policy.for_visit(visit)
        end
      end

      assert_operator queries.length, :<=, 8, "Visit context should be preloaded, not queried per visit."
    end
  end

  def test_daily_batch_rolls_back_its_marker_and_deliveries_then_can_retry
    Database.open do |db|
      Appointment.insert_all!([{
        id: 991001, patient_id: ADULT_PATIENT_ID, clinic_id: AUSTIN_CLINIC_ID,
        start_at: Time.utc(2026, 11, 12, 12), status: "scheduled"
      }, {
        id: 991002, patient_id: ADULT_PATIENT_ID, clinic_id: AUSTIN_CLINIC_ID,
        start_at: Time.utc(2026, 11, 12, 13), status: "scheduled"
      }])
      ClinicSetting.where(clinic_id: AUSTIN_CLINIC_ID).update_all(last_reminder_on: nil)
      sender = FailOnSecondDelivery.new
      flow = ReminderFlow.new(sender: sender)
      before = [Message.count, MessageItem.count, ActivityEvent.count]

      # No surrounding transaction: the public batch method must own its rollback.
      assert_raises(RuntimeError) { flow.run_daily_batch(AUSTIN_CLINIC_ID, TEST_NOW.to_date) }
      assert_equal 2, sender.attempts
      assert_equal before, [Message.count, MessageItem.count, ActivityEvent.count]
      assert_nil ClinicSetting.find(AUSTIN_CLINIC_ID).last_reminder_on
      refute Visit.exists?(appointment_id: [991001, 991002])

      retry_flow = ReminderFlow.new
      assert_operator retry_flow.run_daily_batch(AUSTIN_CLINIC_ID, TEST_NOW.to_date), :>=, 2
      assert_equal TEST_NOW.to_date, ClinicSetting.find(AUSTIN_CLINIC_ID).last_reminder_on
      assert_equal 0, ReminderFlow.new.run_daily_batch(AUSTIN_CLINIC_ID, TEST_NOW.to_date)
    end
  end
end

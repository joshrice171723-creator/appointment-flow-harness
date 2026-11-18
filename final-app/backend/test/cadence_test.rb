require_relative "test_helper"

class CadenceTest < Minitest::Test
  CLINIC_ID = 991
  PATIENT_ID = 991
  APPOINTMENT_ID = 991001
  APPOINTMENT_AT = Time.utc(2026, 11, 12, 12)

  def setup
    restore_demo_fixture
  end

  def with_cadence_visit
    ApplicationRecord.transaction do
      Clinic.insert_all!([{ id: CLINIC_ID, name: "Cadence fixture" }])
      Patient.insert_all!([{
        id: PATIENT_ID, first_name: "Demo", last_name: "Patient",
        birthdate: Date.new(1990, 1, 1), wireless_phone: "(512) 555-0197",
        email: "cadence@example.test", preferred_language: "en"
      }])
      Appointment.insert_all!([{
        id: APPOINTMENT_ID, patient_id: PATIENT_ID, clinic_id: CLINIC_ID,
        start_at: APPOINTMENT_AT, status: "scheduled"
      }])
      ClinicSetting.create!(clinic_id: CLINIC_ID, timezone: "America/Chicago", sender: "+15125550198")
      ContactPermission.create!(patient_id: PATIENT_ID, clinic_id: CLINIC_ID, sms: true, email: true)
      DemoState.where(id: 1).update_all(fail_next: false)
      # Freshness uses real database time while the visit date travels in these tests.
      SourceSync.upsert_all([{ id: 1, last_synced_at: Arel.sql("clock_timestamp()") }])

      yield
      raise ActiveRecord::Rollback
    end
  end

  def flow_at(days_before:)
    day = APPOINTMENT_AT.to_date - days_before
    travel_to(Time.new(day.year, day.month, day.day, 10, 0, 0, "-06:00"))
    ReminderFlow.new
  end

  def messages
    Message.where(clinic_id: CLINIC_ID).order(:id)
  end

  def test_minor_reminder_and_reply_use_only_the_current_authorized_guardian
    with_cadence_visit do
      guardian_id = PATIENT_ID + 1
      Patient.insert_all!([{
        id: guardian_id, first_name: "Authorized", last_name: "Guardian",
        birthdate: Date.new(1980, 1, 1), wireless_phone: "(512) 555-0196",
        email: "guardian@example.test", preferred_language: "en"
      }])
      Patient.where(id: PATIENT_ID).update_all(birthdate: Date.new(2015, 1, 1), guarantor_id: guardian_id)
      permission = ContactPermission.find_by!(patient_id: PATIENT_ID, clinic_id: CLINIC_ID)
      permission.update!(authorized_guarantor_id: guardian_id)
      flow = flow_at(days_before: 7)

      assert_equal 1, flow.run(CLINIC_ID)
      receipt = messages.sole
      assert_equal [PATIENT_ID, guardian_id, "SMS", "+15125550196"],
        receipt.attributes.values_at("patient_id", "recipient_id", "channel", "destination")
      visit = flow.load_visits(CLINIC_ID).sole
      permission.update!(authorized_guarantor_id: nil)
      replies = ReceiveReply.new(now: flow.now)
      assert_equal "Reply sent to Needs attention.", replies.reply(
        visit: visit.reload, text: "YES", receipt: receipt, request_key: "revoked-guardian"
      )
      assert_nil visit.reload.confirmed_at

      permission.update!(authorized_guarantor_id: guardian_id)
      assert_equal "Appointment confirmed.", replies.reply(
        visit: visit.reload, text: "YES", receipt: receipt, request_key: "authorized-guardian"
      )
      assert visit.reload.confirmed_at
    end
  end

  def test_minor_without_an_authorized_guardian_gets_contact_work_instead_of_a_message
    with_cadence_visit do
      Patient.where(id: PATIENT_ID).update_all(birthdate: Date.new(2015, 1, 1))
      flow = flow_at(days_before: 7)

      assert_equal 0, flow.run(CLINIC_ID)
      assert_empty messages
      assert_equal "contact", FollowUpIssue.for_clinic(CLINIC_ID).sole.code
    end
  end

  def test_batch_and_reminder_share_the_ten_to_six_clinic_local_window
    with_cadence_visit do
      { "America/Chicago" => "-06:00", "America/Phoenix" => "-07:00" }.each do |zone, offset|
        ClinicSetting.find(CLINIC_ID).update!(timezone: zone)
        [[9, 59, false], [10, 0, true], [17, 59, true], [18, 0, false]].each do |hour, minute, allowed|
          travel_to(Time.new(2026, 11, 5, hour, minute, 0, offset))
          flow = ReminderFlow.new
          ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)
          visit = flow.load_visits(CLINIC_ID).sole
          batch_due = flow.due_batches.any? { |clinic_id, _day| clinic_id == CLINIC_ID }
          purposes = ReminderSchedule.new(
            visit: visit, now: Time.current, attempts_by_purpose: {}, responded: false, email_available: true
          ).purposes

          assert_equal allowed, batch_due, "Batch at #{hour}:#{minute} in #{zone}"
          assert_equal allowed, purposes.include?("initial"), "Reminder at #{hour}:#{minute} in #{zone}"
        end
      end
    end
  end

  def test_sms_yes_stays_in_its_clinic_even_with_the_same_patient_sender_and_destination
    with_cadence_visit do
      original_flow = flow_at(days_before: 7)
      original_flow.run(CLINIC_ID)
      original_visit = original_flow.load_visits(CLINIC_ID).sole
      original_message = messages.last
      other_clinic_id = CLINIC_ID + 1
      Clinic.insert_all!([{ id: other_clinic_id, name: "Other clinic" }])
      ClinicSetting.create!(clinic_id: other_clinic_id, timezone: "America/Chicago", sender: "+15125550199")
      ContactPermission.create!(patient_id: PATIENT_ID, clinic_id: other_clinic_id, sms: true, email: true)
      Appointment.insert_all!([{
        id: APPOINTMENT_ID + 1, patient_id: PATIENT_ID, clinic_id: other_clinic_id,
        start_at: APPOINTMENT_AT, status: "scheduled"
      }])
      original_flow.run(other_clinic_id)
      other_visit = original_flow.load_visits(other_clinic_id).sole
      other_message = Message.where(clinic_id: other_clinic_id).sole
      # Message history retains the number used then; current clinic senders are unique.
      other_message.update!(sender: original_message.sender)
      assert_equal original_message.destination, other_message.destination

      assert_equal "Appointment confirmed.", ReceiveReply.new(now: original_flow.now).reply(
        visit: original_visit, text: "YES", receipt: original_message, request_key: "clinic-boundary-yes"
      )
      assert original_visit.reload.confirmed_at
      refute other_visit.reload.confirmed_at
      assert_empty FollowUpIssue.where(visit_id: other_visit.id)
    end
  end

  def test_unanswered_visit_gets_sms_email_then_day_before_request_once
    with_cadence_visit do
      assert_equal 1, flow_at(days_before: 7).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 6).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 6).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 5).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 3).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 3).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 1).run(CLINIC_ID)

      assert_equal %w[SMS Email SMS SMS], messages.pluck(:channel)
      assert_includes messages.last.body, "Reply YES"
    end
  end

  def test_confirmation_skips_day_three_and_changes_day_one_wording
    with_cadence_visit do
      flow = flow_at(days_before: 7)
      flow.run(CLINIC_ID)
      flow.load_visits(CLINIC_ID).sole.confirm!(actor: "Patient", at: flow.now)

      assert_equal 0, flow_at(days_before: 6).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 3).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 1).run(CLINIC_ID)
      assert_includes messages.last.body, "No response needed"
      refute_includes messages.last.body, "Reply YES"
      refute_includes messages.last.body, "Reply NO"
    end
  end

  def test_resolved_patient_reply_still_suppresses_day_three
    with_cadence_visit do
      flow = flow_at(days_before: 7)
      flow.run(CLINIC_ID)
      visit = flow.load_visits(CLINIC_ID).sole
      flow.follow_ups.issue(visit, "patient", "Please call me.")

      assert_equal 0, flow_at(days_before: 6).run(CLINIC_ID)
      flow.follow_ups.close_visit_follow_ups(visit, "Called patient.")
      assert_equal 0, flow_at(days_before: 3).run(CLINIC_ID)
    end
  end

  def test_late_booking_combines_due_steps_without_same_day_duplicates
    with_cadence_visit do
      assert_equal 1, flow_at(days_before: 3).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 3).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 1).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 1).run(CLINIC_ID)
      assert_equal 2, messages.count
    end
  end

  def test_confirmation_on_day_three_gets_only_a_courtesy_reminder_afterward
    with_cadence_visit do
      flow_at(days_before: 7).run(CLINIC_ID)
      flow_at(days_before: 6).run(CLINIC_ID)
      flow = flow_at(days_before: 3)
      assert_equal 1, flow.run(CLINIC_ID)
      flow.load_visits(CLINIC_ID).sole.confirm!(actor: "Patient", at: flow.now)

      assert_equal 0, flow_at(days_before: 2).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 1).run(CLINIC_ID)
      assert_includes messages.last.body, "No response needed"
      refute_includes messages.last.body, "Reply YES"
    end
  end

  def test_no_email_permission_skips_day_six_without_an_extra_sms
    with_cadence_visit do
      ContactPermission.where(clinic_id: CLINIC_ID).update_all(email: false)

      assert_equal 1, flow_at(days_before: 7).run(CLINIC_ID)
      assert_equal 0, flow_at(days_before: 6).run(CLINIC_ID)
      assert_equal 1, flow_at(days_before: 3).run(CLINIC_ID)
      assert_equal %w[SMS SMS], messages.pluck(:channel)
    end
  end

  def test_spanish_templates_and_reply_classification
    with_cadence_visit do
      Patient.where(id: PATIENT_ID).update_all(preferred_language: "es-MX")
      flow = flow_at(days_before: 7)
      assert_equal 1, flow.run(CLINIC_ID)
      visit = flow.load_visits(CLINIC_ID).sole
      receipt = messages.last

      assert_includes receipt.body, "Responda SÍ"
      assert_includes receipt.body, "STOP"
      assert_equal "Reply sent to Needs attention.", ReceiveReply.new(now: flow.now).reply(
        visit: visit, text: "Sí, pero llámame", receipt: receipt, request_key: "spanish-review"
      )
      refute flow.load_visits(CLINIC_ID).sole.confirmed_at
      assert_equal "Appointment confirmed.", ReceiveReply.new(now: flow.now).reply(
        visit: visit, text: "sí!", receipt: receipt, request_key: "spanish-yes"
      )

      body = flow.message_templates.message_body(flow.load_visits(CLINIC_ID).sole, "Email", ["courtesy"], language: "es")
      assert_includes body, "No necesita responder"
      refute_includes body, "STOP"
      %w[es es-MX es_US Spanish español].each do |language|
        assert_equal :es, flow.message_templates.message_language(language)
      end
      assert_nil flow.message_templates.message_language("fr")
    end
  end
end

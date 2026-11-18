require_relative "test_helper"

class SeedTest < Minitest::Test
  def setup
    restore_demo_fixture
  end

  def test_assessment_history_runs_real_reminders_replies_and_staff_resolutions_once
    setup_file = ENV["CLINIC_SETUP_FILE"]
    launch = ENV["ASSESSMENT_REMINDERS_START"]
    ENV["CLINIC_SETUP_FILE"] = Rails.root.join("config/clinic-setup.example.json").to_s
    ENV["ASSESSMENT_REMINDERS_START"] = "2026-10-01"
    source_before = PmsReplica.read
    # These October bookings cover email backup, confirmation, no reply, and staff outcomes.
    appointments_by_id = source_before.fetch("appointments").index_by { |row| row.fetch("id") }
    appointments = [49, 50, 52, 53, 54, 57, 59].map { |id| appointments_by_id.fetch(id) }
    appointments[-1] = appointments.last.merge("status" => "complete")
    patient_ids = appointments.map { |row| row.fetch("patient_id") }
    patients = source_before.fetch("patients").select { |row| patient_ids.include?(row.fetch("id")) }
    replay_source = source_before.merge("patients" => patients, "appointments" => appointments)

    Database.open do |db|
      db.transaction do
        WorkflowFixture.clear
        with_replica(replay_source) { load Rails.root.join("db/seeds.rb") }

        report = OperationsQuery.call(now: TEST_NOW)
        october = report.fetch(:rows).find { |row| row["outcome_month"] == "2026-10" && row["clinic_id"] == 1 }
        assert_operator october.fetch("messages_sent"), :>, october.fetch("messaged")
        assert_operator october.fetch("replied"), :>, october.fetch("patient_confirmed")
        assert_operator october.fetch("patient_confirmed"), :>, 0
        assert Message.sent.where(channel: "Email").exists?
        assert_operator Message.sent.minimum(:created_at), :>=, Time.iso8601("2026-10-01T10:00:00-05:00")

        reviews = FollowUpIssue.where(code: %w[patient ambiguous_reply]).includes(:resolution_event).to_a
        refute_empty reviews
        assert reviews.all? { |issue| issue.resolved_at > issue.created_at && issue.resolution_event&.actor == "Taylor Morgan" }
        assert_empty FollowUpCase.where.not(state: "resolved")
        assert_equal source_before, PmsReplica.read
        assert_equal appointments.to_h { |row| row.values_at("id", "status") }, Appointment.pluck(:id, :status).to_h

        counts = [Message.count, ActivityEvent.count, FollowUpIssue.count]
        with_replica(replay_source) { load Rails.root.join("db/seeds.rb") }
        assert_equal counts, [Message.count, ActivityEvent.count, FollowUpIssue.count]
        raise ActiveRecord::Rollback
      end
    end
  ensure
    ENV["CLINIC_SETUP_FILE"] = setup_file
    ENV["ASSESSMENT_REMINDERS_START"] = launch
  end

  def test_app_setup_imports_source_and_configuration_without_creating_history
    previous_file = ENV["CLINIC_SETUP_FILE"]
    ENV["CLINIC_SETUP_FILE"] = Rails.root.join("config/clinic-setup.example.json").expand_path.to_s

    Database.open do |db|
      db.transaction do
        WorkflowFixture.clear
        2.times { load Rails.root.join("db/seeds.rb") }

        assert Appointment.exists?
        assert_equal ["Sam Rivera", "Taylor Morgan"], StaffMember.order(:name).pluck(:name)
        assert_equal "+15125550100", ClinicSetting.sole.sender
        assert_equal 2, ReportingClinicZone.count
        [Visit, Message, MessageItem, ActivityEvent, FollowUpCase, FollowUpIssue, OptOut].each do |model|
          assert_equal 0, model.count, model.name
        end

        raise ActiveRecord::Rollback
      end
    end
  ensure
    ENV["CLINIC_SETUP_FILE"] = previous_file
  end

  def test_seeded_opt_out_has_a_stop_reply_and_keeps_email_available
    Database.open do |db|
      db.transaction do
        permissions = ContactPermission.where(clinic_id: 1)
        assert_empty permissions.where(sms: false).or(permissions.where(email: false))
        opt_out = OptOut.sole
        event = ActivityEvent.find_by!(request_key: "seed-stop")
        receipt = event.message
        assert_equal "STOP", event.body
        assert_equal "Patient", event.actor
        assert_equal "opt_out", event.kind
        assert_equal "SMS", receipt.channel
        assert_equal "sent", receipt.status
        assert_equal opt_out.clinic_id, receipt.clinic_id
        assert_equal opt_out.destination, receipt.destination
        assert_operator event.created_at, :>=, receipt.created_at
        assert_equal event.visit_id, receipt.visits.sole.id
        assert_empty Message.sent.where(channel: "SMS", clinic_id: opt_out.clinic_id,
          destination: opt_out.destination).where("created_at > ?", event.created_at)
        policy = ContactPolicy.new(TEST_NOW)
        contact = policy.for_visit(event.visit)
        channels = policy.destinations(event.visit, contact: contact, opt_outs: [opt_out.destination])
        refute channels.key?("SMS")
        assert_equal contact.email, channels.fetch("Email")
        assert_equal [[161, 190, true, true], [167, 191, true, true]],
          permissions.where(patient_id: [161, 167]).order(:patient_id)
            .pluck(:patient_id, :authorized_guarantor_id, :sms, :email)
      end
    end
  end

  def test_history_is_consistent_with_staff_work_and_exposure
    abort "Use a disposable app database ending in _test." unless URI(ENV.fetch("DENTAL_DATABASE_URL")).path.end_with?("_test")
    Database.open do |db|
      db.transaction do
        assert_equal [
          [23, "Maybe? Which visit is this for?"],
          [26, "Yes, but call me."],
          [102, "NO"]
        ], db.rows(<<~SQL).map { |row| row.values_at("appointment_id", "body") }
          SELECT v.appointment_id,e.body FROM desk.cases k
          JOIN desk.issues i ON i.case_id=k.id AND i.code='patient' AND i.resolved_at IS NULL
          JOIN desk.visits v ON v.id=i.visit_id AND v.current AND v.confirmed_at IS NULL
          JOIN desk.events e ON e.case_id=k.id AND e.visit_id=v.id AND e.kind='reply'
          WHERE k.state='attention' ORDER BY v.appointment_id
        SQL
        missing = db.first_row(<<~SQL).fetch("count")
          SELECT count(*) FROM desk.events e JOIN desk.visits v ON v.id=e.visit_id
          WHERE e.actor='Patient' AND e.kind='reply' AND v.start_at<'2026-11-05'
            AND (e.case_id IS NULL OR NOT EXISTS (
              SELECT 1 FROM desk.issues i WHERE i.case_id=e.case_id AND i.visit_id=v.id AND i.resolved_at IS NOT NULL
            ))
        SQL
        assert_equal 0, missing
        assert_operator 10, :<, db.first_row("SELECT count(*) FROM desk.cases WHERE state='resolved'").fetch("count")
        assert_operator 10, :<, db.first_row("SELECT count(*) FROM desk.issues WHERE resolved_at IS NOT NULL").fetch("count")
        assert_equal 0, db.first_row("SELECT count(*) FROM desk.messages WHERE clinic_id=5").fetch("count")
        assert_equal [7, 6], db.rows(<<~SQL).map { |row| row.fetch("days_before") }
          SELECT v.start_at::date-(m.created_at AT TIME ZONE 'America/Chicago')::date AS days_before
          FROM desk.messages m JOIN desk.message_items i ON i.message_id=m.id
          JOIN desk.visits v ON v.id=i.visit_id WHERE v.appointment_id=102
          ORDER BY m.created_at
        SQL
        assert_equal 0, db.first_row("SELECT count(*) FROM desk.clinic_settings WHERE clinic_id=5").fetch("count")
        assert_equal "America/Phoenix", db.first_row("SELECT timezone FROM desk.reporting_clinic_zones WHERE clinic_id=5").fetch("timezone")
        assert_equal 0, db.first_row(<<~SQL).fetch("count")
          SELECT count(*) FROM desk.events e JOIN desk.issues i ON i.case_id=e.case_id AND i.visit_id=e.visit_id
          WHERE e.body='Please call me.' AND NOT EXISTS (
            SELECT 1 FROM desk.events handled WHERE handled.case_id=e.case_id AND handled.visit_id=e.visit_id
              AND handled.kind='confirmed' AND handled.created_at=i.resolved_at
          )
        SQL
      end
    end
  end

  def test_seeded_receipts_fall_inside_the_sending_window
    Database.open do |db|
      db.transaction do
        outside = db.first_row(<<~SQL).fetch("count")
          SELECT count(*) FROM desk.messages m
          JOIN desk.clinic_settings s ON s.clinic_id=m.clinic_id
          WHERE (m.created_at AT TIME ZONE s.timezone)::time < time '10:00'
             OR (m.created_at AT TIME ZONE s.timezone)::time >= time '18:00'
        SQL
        assert_equal 0, outside
      end
    end
  end

  def test_demo_schedule_has_five_daily_visits_and_bounded_repeat_patients
    first_day = TEST_NOW.to_date.prev_month.beginning_of_month
    austin_days = (first_day..TEST_NOW.to_date.end_of_month).reject(&:sunday?)
    phoenix_days = (first_day..TEST_NOW.to_date.end_of_month).reject(&:sunday?)
    expected_clinic_days = austin_days.length + phoenix_days.length
    expected_clinic_weeks = [austin_days, phoenix_days].sum { |days| days.map(&:beginning_of_week).uniq.length }
    Database.open do |db|
      db.transaction do
        days = db.rows(<<~SQL)
          SELECT clinic_id,start_at::date AS day,count(*) AS visits
          FROM pms.appointments GROUP BY clinic_id,day
        SQL
        assert_equal expected_clinic_days, days.length
        assert days.all? { |day| day["visits"] == 5 && !day["day"].sunday? }

        weeks = db.rows(<<~SQL)
          SELECT clinic_id,week,count(*) FILTER (WHERE visits=3) AS repeat_patients,
            max(visits) AS max_visits,sum(visits) AS total
          FROM (
            SELECT clinic_id,date_trunc('week',start_at) AS week,patient_id,count(*) AS visits
            FROM pms.appointments GROUP BY clinic_id,week,patient_id
          ) patient_weeks
          GROUP BY clinic_id,week
        SQL
        assert_equal expected_clinic_weeks, weeks.length
        weeks.each do |week|
          # The current Phoenix comparison backfill uses one patient per appointment.
          repeated_schedule = week["clinic_id"] == 1 || week["week"].to_date < TEST_NOW.to_date.beginning_of_month
          expected_repeats = repeated_schedule && week["total"] >= 15 ? 1 : 0
          assert_operator week["max_visits"], :<=, 3
          assert_equal expected_repeats, week["repeat_patients"], week.inspect
        end
        visits_per_patient = db.first_row(<<~SQL)
          SELECT max(visits) AS maximum FROM (
            SELECT count(*) AS visits FROM pms.appointments GROUP BY patient_id
          ) totals
        SQL
        assert_operator visits_per_patient.fetch("maximum"), :<=, 6
      end
    end
  end

end

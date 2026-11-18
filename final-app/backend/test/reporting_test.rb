require_relative "test_helper"

class ReportingTest < Minitest::Test
  include Rack::Test::Methods

  def app = Rails.application

  def setup
    url = ENV.fetch("DENTAL_DATABASE_URL", "")
    abort "Set DENTAL_DATABASE_URL to a disposable database ending in _test." unless URI(url).path&.end_with?("_test")
    restore_demo_fixture
    get "/"
    assert last_response.ok?
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
  end

  def test_calendar_and_report_use_the_supplied_status_and_provider
    Database.open do |db|
      db.exec("UPDATE pms.appointments SET status='unscheduled',provider_name=NULL WHERE id=109")
    end
    enter("desk", clinic: 1, staff: 11)
    get "/api/appointments?clinic=1&date=2026-11-04"
    visit = json.fetch("visits").find { |row| row["appointment_id"] == 109 }
    assert_equal "canceled", visit.fetch("outcome")
    assert_nil visit.fetch("provider_name")
    Database.open { |db| db.exec("UPDATE pms.appointments SET status='broken' WHERE id=109") }
    get "/api/appointments?clinic=1&date=2026-11-04"
    assert_equal "rescheduled", json.fetch("visits").find { |row| row["appointment_id"] == 109 }.fetch("outcome")
    enter("apex")
    row = report("2026-11", 1)
    assert_equal row["total"], row.values_at("completed", "rescheduled", "canceled", "unknown").sum
    refute row.key?("no_shows")
    refute row.key?("on_time")
  end

  def test_operations_counts_open_work_on_upcoming_appointments
    enter("apex")

    november = report("2026-11", 1)
    counts = november.fetch("follow_up")
    assert_operator counts.fetch("open"), :>, 0
    assert_equal counts.fetch("total"), counts.fetch("open") + counts.fetch("resolved")
    assert_equal november.fetch("total"), november.values_at("completed", "canceled", "rescheduled", "unknown").sum
  end

  def test_operations_separates_missing_details_guardian_sends_and_reply_work
    travel_to(Time.iso8601("2026-11-30T12:00:00-06:00"))
    enter("apex")
    baseline = report("2026-11", 1).fetch("follow_up")
    Database.open do |db|
      values = { "birthdate" => nil, "wireless_phone" => nil }
      Patient.where(id: 104).update_all(values.merge(ContactComparison.patient_values(Patient.find(104).attributes.merge(values))))
      values = { "wireless_phone" => "number disconnected" }
      Patient.where(id: 102).update_all(values.merge(ContactComparison.patient_values(Patient.find(102).attributes.merge(values))))
    end

    counts = report("2026-11", 1).fetch("follow_up")
    assert_operator counts.fetch("missing_birthdate"), :>, 0
    assert_operator counts.fetch("missing_phone"), :>, 0
    assert_equal baseline.fetch("missing_phone"), counts.fetch("missing_phone")
    assert_equal baseline.fetch("invalid_phone") + 1, counts.fetch("invalid_phone")
    assert_operator counts.fetch("guardian_visits"), :>, 0
    refute counts.key?("yes_call_replies")
    refute counts.key?("yes_call_with_follow_up")
    assert_equal 1, counts.fetch("affirmative_review")
    assert_operator counts.fetch("total"), :>, counts.fetch("resolved")
  end

  def test_month_to_date_shows_elapsed_visits_without_outcomes
    enter("apex")
    baseline = report("2026-11", 1)
    phoenix_baseline = report("2026-11", 5)
    assert_operator phoenix_baseline.fetch("completed"), :>, 0
    Database.open do |db|
      db.exec(<<~SQL)
        UPDATE pms.appointments SET status='scheduled' WHERE id=162;
        UPDATE pms.appointments SET start_at='2026-11-05 08:55',status='scheduled' WHERE id=261;
        UPDATE pms.appointments SET start_at='2026-11-05 09:05',status='scheduled' WHERE id=262;
      SQL
    end
    rows = operations_rows
    austin = report("2026-11", 1, rows: rows)
    assert_equal baseline.fetch("completed") - 1, austin.fetch("completed")
    assert_equal baseline.fetch("unknown") + 1, austin.fetch("unknown")
    assert_equal baseline.fetch("total"), austin.fetch("total")
    phoenix = report("2026-11", 5, rows: rows)
    assert_equal phoenix_baseline.fetch("completed"), phoenix.fetch("completed")
    assert_equal phoenix_baseline.fetch("unknown") + 1, phoenix.fetch("unknown")
    assert_equal phoenix_baseline.fetch("total") + 1, phoenix.fetch("total")
  end

  def test_moved_appointment_keeps_replies_in_the_original_clinic_and_month
    enter("apex")
    travel_to(Time.iso8601("2026-12-06T10:00:00-06:00"))
    original = report("2026-11", 1)
    Database.open do |db|
      db.exec(<<~SQL)
        UPDATE pms.appointments SET clinic_id=5,start_at='2026-12-04 11:00' WHERE id=109;
      SQL
    end
    rows = operations_rows
    assert_equal [1, 0, 0], report("2026-12", 5, rows: rows).values_at("completed", "messaged", "replied")
    assert_equal original.values_at("messaged", "replied"), report("2026-11", 1, rows: rows).values_at("messaged", "replied")
  end

  def test_invalid_reporting_zone_preserves_known_outcomes_without_guessing_elapsed_time
    enter("apex")
    baseline = report("2026-11", 1)
    Database.open do |db|
      db.exec(<<~SQL)
        UPDATE desk.clinic_settings SET timezone='Invalid/Chicago' WHERE clinic_id=1;
        UPDATE pms.appointments SET status='scheduled' WHERE id=162;
      SQL
    end
    austin = report("2026-11", 1)
    assert_equal baseline.fetch("completed") - 1, austin.fetch("completed")
    assert_equal baseline.fetch("unknown"), austin.fetch("unknown")
  end

  def test_staff_visibility_and_scope_are_independent_of_messaging_permission
    Database.open do |db|
      db.exec(<<~SQL)
        DELETE FROM desk.people WHERE patient_id=102 AND clinic_id=1;
        INSERT INTO desk.clinic_settings(clinic_id,timezone,sender) VALUES(5,'America/Phoenix','+16025550100');
        INSERT INTO desk.staff(id,clinic_id,name) VALUES(51,5,'Second clinic staff');
        UPDATE pms.appointments SET patient_id=102,start_at='2026-11-06 12:00',status='scheduled' WHERE id=261;
      SQL
    end
    Database.open { |db| db.transaction { ReconcileAppointments.new(now: Time.current).for_clinic(5) } }
    enter("desk", clinic: 1, staff: 11)
    get "/api/appointments?clinic=1&date=2026-11-06"
    visits = json.fetch("visits")
    assert_equal "Demo Patient 102", visits.find { |visit| visit["appointment_id"] == 102 }.fetch("name")
    refute visits.any? { |visit| visit["appointment_id"] == 261 }
    get "/api/appointments?clinic=5&date=2026-11-06"
    assert_equal 409, last_response.status

    enter("desk", clinic: 5, staff: 51)
    get "/api/appointments?clinic=5&date=2026-11-06"
    visits = json.fetch("visits")
    visit = visits.find { |item| item["appointment_id"] == 261 }
    assert_equal "Demo Patient 102", visit.fetch("name")
    assert_equal "No automated contact permission.", visit.fetch("hold")
    assert_nil visit.fetch("follow_up")
    refute visits.any? { |visit| visit["appointment_id"] == 102 }
    get "/api/board?clinic=1"
    assert_equal 409, last_response.status
  end

  def test_stale_snapshot_is_visible_and_contact_attempt_leaves_the_case_open
    source_url = ENV.fetch("PMS_READER_URL")
    enter("desk", clinic: 1, staff: 11)
    Database.open { |db| db.exec("UPDATE desk.source_sync SET last_synced_at=clock_timestamp()-interval '6 minutes'") }
    unavailable_source = URI(source_url)
    unavailable_source.path += "_unavailable"
    ENV["PMS_READER_URL"] = unavailable_source.to_s
    get "/api/board?clinic=1"
    board = json
    assert board.fetch("sync_status").fetch("stale")
    follow_up = board.fetch("cases").find { |entry| entry["name"] == "Demo Patient 102" }
    path = "/api/work/#{follow_up.fetch('id')}"
    get path
    detail = json
    assert detail.fetch("sync_status").fetch("stale")
    send_json(path, outcome: "claim", version: detail.fetch("case").fetch("version"))
    get path
    claimed = json
    assert claimed.fetch("sync_status").fetch("stale")
    issue = claimed.fetch("issues").find { |item| item["code"] == "patient" }
    version = claimed.fetch("case").fetch("version")
    body = { outcome: "attempted", issue: issue.fetch("id"), note: "Called and left a callback number.", version: version }
    send_json(path, **body)
    get path
    attempted = json
    assert_equal ["progress", 11], attempted.fetch("case").values_at("state", "owner_id")
    assert_nil attempted.fetch("issues").find { |item| item["id"] == issue["id"] }.fetch("resolved_at")
    assert attempted.fetch("history").any? { |event| event["kind"] == "attempted" && event["body"] == body[:note] }
    Database.open { |db| db.exec("UPDATE desk.source_sync SET last_synced_at=clock_timestamp()-interval '6 minutes'") }
    post path, JSON.generate(body)
    assert_equal 409, last_response.status
    get path
    assert json.fetch("sync_status").fetch("stale")
    version = json.fetch("case").fetch("version")
    %w[confirmed canceled rescheduled].each do |outcome|
      post path, JSON.generate(body.merge(outcome: outcome, version: version))
      assert_equal 409, last_response.status
      assert_match(/could not be refreshed/, JSON.parse(last_response.body).fetch("error"))
    end
    ENV["PMS_READER_URL"] = source_url
    send_json(path, **body.merge(outcome: "confirmed", version: version))
    get path
    refute json.fetch("sync_status").fetch("stale")
  ensure
    ENV["PMS_READER_URL"] = source_url
  end

  def test_cancellation_closes_the_reply_and_earlier_no_response_for_only_that_visit
    case_id, token = Database.open do |db|
      db.transaction do
        flow = ReminderFlow.new
        ReconcileAppointments.new(now: flow.now).for_clinic(1)
        visits = flow.load_visits(1).index_by(&:appointment_id)
        first = visits.fetch(171)
        second = visits.fetch(177)
        case_id = flow.follow_ups.issue(first, "no_response", "Call about the first appointment.")
        flow.follow_ups.issue(second, "no_response", "Call about the second appointment.")
        email_receipt = <<~SQL
          SELECT m.token FROM desk.messages m JOIN desk.message_items i ON i.message_id=m.id
          WHERE i.visit_id=$1 AND m.channel='Email' AND m.status='sent'
        SQL
        receipt = db.first_row(email_receipt, first.id)
        unless receipt
          flow.reminder_sender.deliver(visit: first, channel: "Email", destination: first.patient.email, purposes: ["backup"], recipient_id: first.patient_id)
          receipt = db.first_row(email_receipt, first.id)
        end
        [case_id, receipt.fetch("token")]
      end
    end
    enter("patient")
    get "/api/patient"
    send_json("/api/patient/messages/#{token}", body: "NO", key: json.fetch("key"))
    enter("desk", clinic: 1, staff: 11)
    path = "/api/work/#{case_id}"
    get path
    send_json(path, outcome: "claim", version: json.fetch("case").fetch("version"))
    get path
    claimed = json
    reply = claimed.fetch("issues").find { |issue| issue["code"] == "patient" }
    send_json(path, outcome: "clarified", issue: reply.fetch("id"), appointment_ids: [171],
              note: "The patient clarified that this reply concerns the first appointment.",
              version: claimed.fetch("case").fetch("version"))
    get path
    clarified = json
    outcome_issue = clarified.fetch("issues").find do |issue|
      issue["appointment_id"] == 171 && issue["code"] == "patient" && !issue["resolved_at"] && !issue["reply"]
    end
    send_json(path, outcome: "canceled", issue: outcome_issue.fetch("id"),
              note: "Canceled in the PMS after the patient declined.", version: clarified.fetch("case").fetch("version"))
    get path
    saved = json
    open_issues = saved.fetch("issues").select { |issue| issue["resolved_at"].nil? }
    assert_equal [[177, "no_response"]], open_issues.map { |issue| issue.values_at("appointment_id", "code") }
    assert_equal ["progress", 11], saved.fetch("case").values_at("state", "owner_id")
  end

  def test_resolved_cards_use_recorded_resolution_not_current_owner
    Database.open do |db|
      db.transaction do
        flow = ReminderFlow.new
        ReconcileAppointments.new(now: flow.now).for_clinic(1)
        patients_with_cases = FollowUpCase.where(clinic_id: 1).pluck(:patient_id)
        visit = flow.load_visits(1, current: false).find do |row|
          row.starts_at_utc < flow.now && !patients_with_cases.include?(row.patient_id)
        end
        case_id = flow.follow_ups.issue(visit, "fixture", "Imported history without an actor.")
        db.rows("UPDATE desk.issues SET resolved_at=$2 WHERE case_id=$1", case_id, flow.now)
        flow.follow_ups.finish_cases(1)
      end
    end
    enter("desk", clinic: 1, staff: 11)
    get "/api/board?clinic=1"
    cases = json.fetch("cases")
    manual = cases.find { |entry| entry.dig("resolution", "kind") == "canceled" }
    assert_equal "Taylor Morgan", manual.dig("resolution", "actor")
    assert_nil manual["owner"]
    assert manual.dig("resolution", "at")
    assert cases.any? { |entry| entry.dig("resolution", "actor") == "Patient" }
    unknown = cases.find { |entry| entry["state"] == "resolved" && entry.dig("resolution", "actor").nil? }
    assert unknown
    assert_nil cases.find { |entry| entry["state"] == "attention" }["resolution"]
    Database.open do |db|
      flow = ReminderFlow.new
      db.transaction do
        manual_issue = db.first_row("SELECT * FROM desk.issues WHERE case_id=$1 ORDER BY resolved_at DESC LIMIT 1", manual["id"])
        ActivityEvent.record(at: flow.now, actor: "Appointment Flow", kind: "follow_up_resolved",
                             body: "Staff recorded a cancellation.",
                             case_id: manual["id"], visit_id: manual_issue["visit_id"])
        db.rows("UPDATE desk.events SET body='Canceled after speaking with the patient.' WHERE id=$1", manual_issue["resolution_event_id"])
        unknown_issue = db.first_row("SELECT * FROM desk.issues WHERE case_id=$1 LIMIT 1", unknown["id"])
        db.rows("UPDATE desk.issues SET resolved_at=NULL WHERE id=$1", unknown_issue["id"])
        visit = flow.load_visits(1, current: false, ids: [unknown_issue["visit_id"]]).first
        flow.follow_ups.close_visit_follow_ups(visit, "The PMS marked this visit complete.")
      end
    end
    get "/api/board?clinic=1"
    updated = json.fetch("cases").index_by { |entry| entry["id"] }
    assert_equal "Taylor Morgan", updated.fetch(manual["id"]).dig("resolution", "actor")
    assert_equal "follow_up_resolved", updated.fetch(unknown["id"]).dig("resolution", "kind")
    get "/api/work/#{manual['id']}"
    assert_equal updated.fetch(manual["id"])["resolution"], json.fetch("case")["resolution"]
  end

  def test_repeated_dst_hour_uses_the_same_cutoff_as_the_replica_report
    Database.open do |db|
      db.exec("UPDATE pms.appointments SET status='scheduled',start_at='2026-11-01 01:30' WHERE id=109")
      travel_to(Time.iso8601("2026-11-01T06:45:00Z"))
      before = OperationsQuery.call[:rows].find { |row| row["outcome_month"] == "2026-11" && row["clinic_id"] == 1 }
      travel_to(Time.iso8601("2026-11-01T07:45:00Z"))
      after = OperationsQuery.call[:rows].find { |row| row["outcome_month"] == "2026-11" && row["clinic_id"] == 1 }
      assert_equal (before&.fetch("unknown") || 0) + 1, after.fetch("unknown")
    end
  end

  def test_report_aggregates_without_instantiating_source_or_workflow_records
    instantiated = []
    subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |event|
      instantiated << event.payload.fetch(:class_name)
    end
    rows = OperationsQuery.call(now: TEST_NOW, month: "current").fetch(:rows)
    assert rows.any?
    assert_empty instantiated & %w[Appointment Patient Message MessageItem Visit FollowUpIssue]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_non_patient_message_events_do_not_change_report_counts
    before = OperationsQuery.call(now: TEST_NOW)
    message = Message.sent.first!
    ActivityEvent.record(actor: "Transport", kind: "reply", body: "YES", at: TEST_NOW,
      message_id: message.id, visit_id: message.items.first!.visit_id)
    assert_equal before, OperationsQuery.call(now: TEST_NOW)
  end

  def test_skipped_dst_hour_uses_postgres_wall_time_interpretation
    Appointment.where(id: 162).update_all(status: "scheduled", start_at: Time.utc(2027, 3, 14, 2, 30))
    before = OperationsQuery.call(now: Time.utc(2027, 3, 14, 8, 29)).fetch(:rows)
      .find { |row| row.values_at("clinic_id", "outcome_month") == [1, "2027-03"] }
    after = OperationsQuery.call(now: Time.utc(2027, 3, 14, 8, 30)).fetch(:rows)
      .find { |row| row.values_at("clinic_id", "outcome_month") == [1, "2027-03"] }
    assert_equal 0, before.fetch("total")
    assert_equal 1, after.fetch("unknown")
  end

  def test_operations_month_only_loads_that_months_details
    full = OperationsQuery.call(now: TEST_NOW)
    month = full.fetch(:activity_month)
    selected = OperationsQuery.call(now: TEST_NOW, month: month)
    full_rows = full.fetch(:rows)
    selected_rows = selected.fetch(:rows)
    assert_equal full_rows.map { |row| row.except("follow_up", "contact_holds") },
      selected_rows.map { |row| row.except("follow_up", "contact_holds") }
    assert_equal full_rows.select { |row| row.fetch("outcome_month") == month },
      selected_rows.select { |row| row.fetch("outcome_month") == month }
    older_rows = selected_rows.reject { |row| row.fetch("outcome_month") == month }
    assert older_rows.any?
    assert older_rows.all? { |row| row.fetch("follow_up").values.all?(&:zero?) && row.fetch("contact_holds").empty? }
  end

  private

  def enter(workspace, **options)
    send_json("/api/enter", workspace: workspace, **options)
  end

  def report(month, clinic, rows: operations_rows)
    rows.find { |row| row["outcome_month"] == month && row["clinic_id"] == clinic }
  end

  def operations_rows
    get "/api/operations"
    json.fetch("rows")
  end

  def send_json(path, **body)
    post path, JSON.generate(body)
    json
  end

  def json
    assert last_response.ok?, last_response.body
    JSON.parse(last_response.body)
  end

end

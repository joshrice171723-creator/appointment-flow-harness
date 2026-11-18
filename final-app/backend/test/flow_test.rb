require_relative "test_helper"

class FlowTest < Minitest::Test
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

  def json
    assert last_response.ok?, last_response.body
    JSON.parse(last_response.body)
  end

  def send_json(path, **params)
    post path, JSON.generate(params)
    json
  end

  def run_reminders
    Database.open do |db|
      db.transaction do
        flow = ReminderFlow.new
        PmsSnapshot.new.refresh
        Clinic.messaging_enabled.sum { |clinic| flow.run(clinic.id) }
      end
    end
  end

  def open_desk
    send_json("/api/enter", workspace: "desk", clinic: 1, staff: 11)
  end

  def pms_snapshot(as_of: nil)
    return PmsReplica.read unless as_of
    original = Time.current
    travel_to(Time.iso8601(as_of))
    PmsReplica.read
  ensure
    travel_to(original) if original
  end

  def visits
    get "/api/appointments?clinic=1"
    json.fetch("visits")
  end

  def receipt_token(visit, channel)
    Database.open do |db|
      db.first_row(<<~SQL, visit.fetch("appointment_id"), channel).fetch("token")
        SELECT m.token FROM desk.messages m JOIN desk.message_items i ON i.message_id=m.id
        JOIN desk.visits v ON v.id=i.visit_id
        WHERE v.appointment_id=$1 AND m.channel=$2 AND m.status='sent' ORDER BY m.id DESC LIMIT 1
      SQL
    end
  end

  def send_reply(visit, text, channel, token: receipt_token(visit, channel))
    send_json("/api/enter", workspace: "patient")
    patient_id = Database.open do |db|
      db.exec_params("SELECT patient_id FROM desk.messages WHERE token=$1", [token]).first.fetch("patient_id")
    end
    get "/api/patient", clinic: 1, patient: patient_id
    inbox = json
    preview = inbox.fetch("messages").find { |message| message["token"] == token }
    refute_includes preview.fetch("body"), "/p/"
    result = send_json("/api/patient/messages/#{token}", body: text, key: inbox.fetch("key"))
    open_desk
    result
  end

  def test_reply_review_and_confirmation
    open_desk
    noah = visits.find { |visit| visit["appointment_id"] == 103 }
    assert_equal "Reply sent to Needs attention.", send_reply(noah, "Yes, but call me.", "Email")["message"]
    Database.open do |db|
      db.exec(<<~SQL)
        INSERT INTO desk.events(visit_id,message_id,created_at,actor,kind,body)
        SELECT e.visit_id,m.id,m.created_at,'Fake Email','sent','initial'
        FROM desk.events e JOIN desk.messages m ON m.id=e.message_id
        WHERE m.patient_id=103 AND e.kind='reply'
      SQL
    end
    noah = visits.find { |visit| visit["appointment_id"] == 103 }
    assert_nil noah["confirmed_at"]
    path = "/api/work/#{noah.fetch('reply').fetch('case_id')}"
    get path
    work = json
    assert_equal "Old number: 512-555-0103", work.fetch("person").fetch("phone_on_file")
    assert_nil work.fetch("person").fetch("contact").fetch("phone")
    assert_equal "Dr. Jordan Patel", work.fetch("issues").first.fetch("provider_name")
    history = work.fetch("history")
    reply = history.select { |entry| entry["kind"] == "reply" }.sole
    receipt = history.select { |entry| entry["entry_type"] == "receipt" }.sole
    refute history.any? { |entry| entry["entry_type"] == "event" && entry["kind"] == "sent" }
    assert history.any? { |entry| entry["kind"] == "issue_opened" && entry["body"] == "Clarify this patient reply." }
    review = work.fetch("issues").find { |item| item["reply"] }
    assert_equal "Yes, but call me.", review.fetch("reply").fetch("body")
    assert_equal [103], review.fetch("candidate_appointments").map { |item| item.fetch("appointment_id") }
    assert_equal ["event", "reply", "Yes, but call me."], reply.values_at("entry_type", "kind", "body")
    assert_equal ["receipt", "Email", "sent", "initial"], receipt.values_at("entry_type", "actor", "kind", "purposes")
    assert_includes receipt.fetch("body"), "Responda SÍ para confirmar"
    assert_operator reply.fetch("created_at"), :>, receipt.fetch("created_at")
    send_json(path, outcome: "claim", version: work.fetch("case").fetch("version"))
    get path
    work = json
    send_json(path, outcome: "clarified", version: work.fetch("case").fetch("version"),
      issue: review.fetch("id"), appointment_ids: [103], note: "Reply applies to this appointment.")
    get path
    work = json
    issue = work.fetch("issues").find { |item| item["code"] == "patient" && !item["reply"] && !item["resolved_at"] }
    send_json(path, outcome: "confirmed", version: work.fetch("case").fetch("version"), issue: issue["id"], note: "Verified by phone.")
    noah = visits.find { |visit| visit["appointment_id"] == 103 }
    refute_nil noah["confirmed_at"]
    assert_nil noah["reply"]
  end

  def test_staff_cannot_read_another_clinics_appointments
    open_desk
    get "/api/appointments?clinic=3"
    assert_equal 409, last_response.status
  end

  def test_reminder_run_and_repeat
    travel_to(TEST_NOW + 24.hours)
    assert_operator run_reminders, :>, 0
    assert_equal 0, run_reminders
  end

  def test_daily_batch_uses_clinic_time_and_runs_once_even_after_restarting
    Database.open do |db|
      rollback_fixture(db) do
        assert_equal [[1, TEST_NOW.to_date]], ReminderFlow.new.due_batches
        travel_to(TEST_NOW - 1.minute)
        assert_empty ReminderFlow.new.due_batches
        travel_to(TEST_NOW)
        flow = ReminderFlow.new
        flow.run_daily_batch(1, TEST_NOW.to_date)
        assert_empty ReminderFlow.new.due_batches
        assert_equal 0, ReminderFlow.new.run_daily_batch(1, TEST_NOW.to_date)

        travel_to(TEST_NOW + 1.day)
        assert_equal [[1, TEST_NOW.to_date + 1]], ReminderFlow.new.due_batches
        assert_operator ReminderFlow.new.run_daily_batch(1, TEST_NOW.to_date + 1), :>, 0
      end
    end
  end

  def test_worker_refreshes_the_shared_cache_without_get_mutations_or_early_sends
    travel_to(TEST_NOW - 5.minutes)
    open_desk
    before = Database.open do |db|
      db.exec("UPDATE desk.source_sync SET last_synced_at=clock_timestamp()-interval '6 minutes'")
      db.exec("SELECT count(*) FROM desk.messages").first.fetch("count")
    end
    get "/api/board?clinic=1"
    assert json.fetch("sync_status").fetch("stale")
    ReminderRunner.tick
    get "/api/board?clinic=1"
    refreshed = json.fetch("sync_status")
    refute refreshed.fetch("stale")

    get "/api/board?clinic=1"
    assert_equal refreshed, json.fetch("sync_status")
    assert_equal before, Database.open { |db| db.exec("SELECT count(*) FROM desk.messages").first.fetch("count") }
  end

  def test_import_grants_new_contacts_without_restoring_revoked_channels
    Database.open do |db|
      rollback_fixture(db) do
        flow = ReminderFlow.new
        patient_id = 990124
        snapshot = PmsReplica.read
        snapshot.fetch("patients") << {
          "id" => patient_id, "first_name" => "Fresh", "last_name" => "Patient",
          "birthdate" => "1980-01-01", "wireless_phone" => "512-555-0124", "email" => "new@example.test"
        }
        snapshot.fetch("appointments") << {
          "id" => patient_id, "patient_id" => patient_id, "clinic_id" => 1,
          "start_at" => "2026-11-06 12:30", "status" => "scheduled"
        }

        with_replica(snapshot) do
          PmsSnapshot.new.refresh
          permission = ContactPermission.find_by!(patient_id: patient_id, clinic_id: 1)
          assert permission.sms
          assert permission.email
          assert_nil permission.authorized_guarantor_id
          flow.run(1)
          visit = Visit.current.find_by!(appointment_id: patient_id)
          receipt = Message.sent.where(patient_id: patient_id).sole
          assert_equal "SMS", receipt.channel

          assert_equal "Texts stopped for this number.", ReceiveReply.new(now: flow.now).reply(
            visit: visit, text: "STOP", receipt: receipt, request_key: "new-contact-stop"
          )
          permission.update!(email: false)
          PmsSnapshot.new.refresh
          refute permission.reload.email, "A refresh must preserve an explicit channel revocation."
          assert OptOut.exists?(clinic_id: 1, destination: receipt.destination)
          loaded = flow.load_visits(1, ids: [visit.id]).sole
          destinations = flow.contact_policy.destinations(
            loaded, contact: flow.contact_policy.for_visit(loaded),
            opt_outs: OptOut.where(clinic_id: 1).pluck(:destination).to_set
          )
          assert_empty destinations
        end
      end
    end
  end
  def test_invalid_timezone_holds_sends_and_dst_wall_times_are_rejected
    Database.open do |db|
      rollback_fixture(db) do
        flow = ReminderFlow.new
        assert_nil Visit.clinic_wall_time_to_utc(Time.utc(2026, 11, 1, 1, 30), "America/Chicago")
        assert_nil Visit.clinic_wall_time_to_utc(Time.utc(2026, 3, 8, 2, 30), "America/Chicago")
        db.rows("UPDATE desk.clinic_settings SET timezone='America/Unmapped' WHERE clinic_id=1")
        assert_equal 0, flow.run(1)
        visit = flow.load_visits(1).find { |item| item["appointment_id"] == 123 }
        assert_equal "Appointment time needs review.", flow.contact_policy.hold(visit)
      end
    end
  end

  def test_failed_snapshot_preserves_old_cache_and_prevents_auto_confirmation
    source_url = ENV["PMS_READER_URL"]
    open_desk
    kelly = visits.find { |visit| visit["appointment_id"] == 123 }
    before = Database.open do |db|
      flow = ReminderFlow.new
      db.rows("UPDATE desk.source_sync SET last_synced_at=clock_timestamp()-interval '6 minutes'")
      assert SourceSync.status["stale"]
      refute SourceSync.status.key?("demo_now")
      assert_equal 0, db.transaction { flow.run(1) }
      SourceSync.status.fetch("last_synced_at")
    end
    unavailable_source = URI(source_url)
    unavailable_source.path += "_unavailable"
    ENV["PMS_READER_URL"] = unavailable_source.to_s
    error = assert_raises(ReminderFlow::Conflict) { run_reminders }
    assert_match(/PMS snapshot unavailable/, error.message)
    assert_equal before, SourceSync.status.fetch("last_synced_at")
    assert_equal "Reply sent to Needs attention.", send_reply(kelly, "YES", "SMS")["message"]
    refute visits.find { |visit| visit["appointment_id"] == 123 }.fetch("confirmed_at")
  ensure
    ENV["PMS_READER_URL"] = source_url
  end

  def test_reminder_timing_and_successful_email_recovery_close_delivery_work
    Database.open do |db|
      rollback_fixture(db) do
        db.exec(<<~SQL)
          INSERT INTO pms.clinics(id,name) VALUES(991,'Cadence fixture');
          INSERT INTO desk.clinic_settings(clinic_id,timezone,sender)
          VALUES(991,'America/Chicago','+15125550198');
          INSERT INTO desk.people(patient_id,clinic_id,sms,email) VALUES(111,991,true,true);
          INSERT INTO pms.appointments(id,patient_id,clinic_id,start_at,status)
          VALUES(991001,111,991,'2026-11-12 12:00','scheduled');
        SQL
        at = ->(time) do
          travel_to(Time.parse(time))
          ReminderFlow.new
        end
        assert_equal 0, at.call("2026-11-05 09:59-06").run(991)
        assert_equal 0, at.call("2026-11-05 18:00-06").run(991)
        assert_equal 0, at.call("2026-11-06 09:00-06").run(991)
        flow = at.call("2026-11-06 10:00-06")
        db.rows("UPDATE desk.demo SET fail_next=true WHERE id=1")
        assert_equal 2, flow.run(991)
        attempts = db.rows(<<~SQL)
          SELECT m.id,m.channel,m.destination,m.sender,m.recipient_id,m.status,i.visit_id,i.purpose
          FROM desk.messages m JOIN desk.message_items i ON i.message_id=m.id
          WHERE m.clinic_id=991 ORDER BY m.id
        SQL
        assert_equal [["SMS", "failed", "initial"], ["Email", "sent", "backup"]],
          attempts.map { |row| row.values_at("channel", "status", "purpose") }
        visit = flow.load_visits(991).first
        receipt = attempts.last
        before_window = at.call("2026-11-10 11:59-06")
        before_window.run(991)
        assert_nil db.first_row("SELECT id FROM desk.issues WHERE visit_id=$1 AND code='no_response'", visit["id"])
        flow = at.call("2026-11-10 12:00-06")
        flow.run(991)
        assert db.first_row("SELECT id FROM desk.issues WHERE visit_id=$1 AND code='no_response' AND resolved_at IS NULL", visit["id"])
        assert_equal "Appointment confirmed.", ReceiveReply.new(now: flow.now).reply(visit: visit, text: "YES", receipt: Message.find(receipt.fetch("id")), request_key: SecureRandom.hex(16))
        assert_equal "resolved", db.first_row("SELECT state FROM desk.cases WHERE clinic_id=991").fetch("state")
        assert_equal 0, at.call("2026-11-11 09:59-06").run(991)
        assert_equal 1, at.call("2026-11-11 10:00-06").run(991)
        assert_equal "courtesy", db.first_row("SELECT purpose FROM desk.message_items WHERE visit_id=$1 ORDER BY message_id DESC LIMIT 1", visit["id"]).fetch("purpose")
      end
    end
  end

  def rollback_fixture(db)
    ApplicationRecord.connection.begin_transaction
    ApplicationRecord.connection.materialize_transactions
    yield
  ensure
    ApplicationRecord.connection.rollback_transaction
  end

  def test_elapsed_time_does_not_invent_attendance_and_closes_old_follow_ups
    before = pms_snapshot
    travel_to(TEST_NOW + 72.hours)
    run_reminders
    assert_equal before, pms_snapshot
    open_desk
    get "/api/appointments?clinic=1&date=2026-11-05"
    visit = json.fetch("visits").find { |row| row["appointment_id"] == 104 }
    assert_equal ["scheduled", "unknown"], visit.values_at("status", "outcome")
    get "/api/board?clinic=1"
    assert_equal "resolved", json.fetch("cases").find { |entry| entry["name"] == "Demo Patient 102" }.fetch("state")
  end

  def test_reminder_run_uses_email_when_the_phone_field_contains_a_note
    Database.open do |db|
      ApplicationRecord.connection.begin_transaction
      ApplicationRecord.connection.materialize_transactions
      flow = ReminderFlow.new
      db.rows("UPDATE pms.patients SET wireless_phone=$1 WHERE id=103", "Old number: 512-555-0103")
      db.rows(<<~SQL)
        DELETE FROM desk.message_items i USING desk.visits v
        WHERE i.visit_id=v.id AND v.appointment_id=103
      SQL

      flow.run(1)

      attempts = db.rows(<<~SQL)
        SELECT DISTINCT m.channel,m.destination FROM desk.messages m
        JOIN desk.message_items i ON i.message_id=m.id JOIN desk.visits v ON v.id=i.visit_id
        WHERE v.appointment_id=103
      SQL
      assert_equal [{"channel" => "Email", "destination" => "noah.103@example.test"}], attempts
    ensure
      ApplicationRecord.connection.rollback_transaction
    end
  end

  def test_leadership_report_totals_and_scope
    send_json("/api/enter", workspace: "apex")
    get "/api/operations"
    rows = json.fetch("rows")
    assert_equal %w[2026-10 2026-11], rows.map { |row| row.fetch("outcome_month") }.uniq.sort
    october = rows.select { |row| row["outcome_month"] == "2026-10" }
    assert_equal 2, october.length
    austin, phoenix = october.sort_by { |row| row.fetch("clinic_id") }
    previous_month = TEST_NOW.to_date.prev_month
    open_days = (previous_month.beginning_of_month..previous_month.end_of_month).count { |day| !day.sunday? }
    expected_monthly_visits = open_days * 5
    assert_equal expected_monthly_visits, austin["total"]
    assert_equal expected_monthly_visits, phoenix["total"]
    assert_operator austin["completed"].fdiv(austin["total"]), :>, phoenix["completed"].fdiv(phoenix["total"])
    october.each do |row|
      assert_equal row["total"], row.values_at("completed", "rescheduled", "canceled", "unknown").sum
    end
    assert_operator austin["replied"], :>, 0
    assert_equal 0, phoenix["messaged"]
    assert_equal [1, 5], rows.select { |row| row["outcome_month"] == "2026-11" }.map { |row| row["clinic_id"] }.sort

    open_desk
    get "/api/operations"
    assert_equal 409, last_response.status
    get "/api/appointments?clinic=5"
    assert_equal 409, last_response.status
  end

  def test_routine_source_edit_preserves_confirmation
    open_desk
    kelly = visits.find { |visit| visit["appointment_id"] == 123 }
    assert_equal "Appointment confirmed.", send_reply(kelly, "YES", "SMS")["message"]
    Database.open do |db|
      db.exec("UPDATE pms.appointments SET updated_at=updated_at+interval '1 minute',length_minutes=45 WHERE id=123")
    end
    Database.open { |db| db.transaction { ReconcileAppointments.new(now: Time.current).for_clinic(1) } }
    assert visits.find { |visit| visit["appointment_id"] == 123 }["confirmed_at"]
  end

  def test_stop_preserves_permitted_email_fallback
    open_desk
    robin = visits.find { |visit| visit["appointment_id"] == 110 }
    assert_equal "Texts stopped for this number.", send_reply(robin, "STOP", "SMS")["message"]
    travel_to(TEST_NOW + 24.hours)
    run_reminders
    Database.open do |db|
      result = db.exec_params(<<~SQL, [robin.fetch("appointment_id")]).to_a
        SELECT DISTINCT m.channel FROM desk.messages m JOIN desk.message_items i ON i.message_id=m.id
        JOIN desk.visits v ON v.id=i.visit_id WHERE v.appointment_id=$1 AND v.current
      SQL
      assert_equal ["Email"], result.map { |row| row.fetch("channel") }
    end
  end

  def test_patient_workspace_is_separate
    open_desk
    get "/api/patient"
    assert_equal 409, last_response.status
    send_json("/api/enter", workspace: "patient")
    get "/api/board"
    assert_equal 409, last_response.status
    get "/api/operations"
    assert_equal 409, last_response.status
    get "/api/patient", clinic: 1, patient: 102
    inbox = json
    assert_equal [1], inbox.fetch("clinics").map { |clinic| clinic.fetch("id") }
    assert_equal [1], inbox.fetch("patients").map { |patient| patient["clinic_id"] }.uniq
    assert_equal %w[Email SMS], inbox.fetch("messages").map { |message| message.fetch("channel") }.uniq.sort
    maya = inbox.fetch("messages").find { |message| message["patient_id"] == 102 && message["channel"] == "SMS" }
    assert_includes maya.fetch("body"), "Nov 6, 2026 at 11:00 AM local time, Austin"
    refute_includes maya.fetch("body"), "Demo Patient 102"
    assert inbox.fetch("replies").any? { |reply| reply["token"] == maya["token"] && reply["body"].start_with?("NO") }
    post "/api/patient/messages/missing", JSON.generate(body: "YES", key: inbox.fetch("key"))
    assert_equal 409, last_response.status
  end

  def test_calendar_and_resolved_examples
    open_desk
    get "/api/appointments?clinic=1&date=today"
    calendar = json
    assert_equal "2026-11-05", calendar.fetch("date")
    assert_equal "2026-11-02", calendar.fetch("week")
    assert_equal 30, calendar.fetch("visits").length
    grace = calendar.fetch("visits").find { |visit| visit["appointment_id"] == 109 }
    refute_nil grace.fetch("confirmed_at")
    assert_equal "Dr. Avery Lee", grace.fetch("provider_name")

    get "/api/appointments?clinic=1&date=2026-10-15"
    historical = json.fetch("visits")
    assert historical.any? { |visit| visit["outcome"] == "completed" }
    assert historical.any? { |visit| %w[rescheduled canceled].include?(visit["outcome"]) }

    get "/api/board?clinic=1"
    assert json.fetch("cases").any? { |entry| entry["name"] == "Demo Patient 109" && entry["state"] == "resolved" }
  end

  def test_historical_no_replies_are_visible_without_reopening_follow_ups
    counts, sample = Database.open do |db|
      counts = db.first_row(<<~SQL)
        SELECT count(DISTINCT v.id) AS reminded,
          count(DISTINCT v.id) FILTER (WHERE e.kind='reply' AND e.body ~* '^no\\M') AS replied_no
        FROM desk.message_items i JOIN desk.visits v ON v.id=i.visit_id
        JOIN desk.messages m ON m.id=i.message_id AND m.status='sent'
        LEFT JOIN desk.events e ON e.message_id=m.id
        WHERE v.clinic_id=1 AND v.start_at>='2026-10-01' AND v.start_at<'2026-11-01'
      SQL
      sample = db.first_row(<<~SQL)
        SELECT v.appointment_id,v.start_at::date AS day,e.case_id,e.body,a.status,CASE a.status WHEN 'broken' THEN 'rescheduled' ELSE 'canceled' END AS outcome
        FROM desk.events e JOIN desk.visits v ON v.id=e.visit_id
        JOIN pms.appointments a ON a.id=v.appointment_id
        WHERE e.kind='reply' AND e.body='NO' AND v.start_at<'2026-11-01'
        ORDER BY v.start_at LIMIT 1
      SQL
      [counts, sample]
    end
    assert_in_delta 0.10, counts.fetch("replied_no").fdiv(counts.fetch("reminded")), 0.01

    open_desk
    get "/api/appointments?clinic=1&date=#{sample.fetch('day')}"
    visit = json.fetch("visits").find { |item| item["appointment_id"] == sample.fetch("appointment_id") }
    assert_equal sample.fetch("case_id"), visit.fetch("declined_reply").fetch("case_id")
    assert_equal sample.fetch("outcome"), visit.fetch("outcome")
    assert_includes %w[canceled rescheduled], visit.fetch("outcome")
    assert_equal sample.fetch("status"), visit.fetch("status")
    assert_nil visit.fetch("confirmed_at")
    assert_nil visit.fetch("reply")

    get "/api/work/#{sample.fetch('case_id')}"
    work = json
    assert_equal "resolved", work.fetch("case").fetch("state")
    assert_includes work.fetch("history").map { |event| event["body"] }, sample.fetch("body")
    assert_includes work.fetch("history").map { |event| event["kind"] }, sample.fetch("outcome")
  end

  def test_patient_flow_retires_past_follow_ups_but_preserves_history
    open_desk
    maya, noah = visits.index_by { |visit| visit.fetch("appointment_id") }.values_at(102, 103)
    send_reply(noah, "Please call me.", "Email")
    Database.open do |db|
      db.transaction do
        flow = ReminderFlow.new
        db.exec(<<~SQL)
          INSERT INTO pms.appointments(id,patient_id,clinic_id,start_at,status)
          SELECT 990102,patient_id,clinic_id,start_at+interval '3 days',status
          FROM pms.appointments WHERE id=102;
        SQL
        ReconcileAppointments.new(now: flow.now).for_clinic(1)
        future = flow.load_visits(1).find { |visit| visit["appointment_id"] == 990102 }
        flow.follow_ups.issue(future, "no_response", "Confirmation needed for the upcoming visit.")
        db.exec(<<~SQL)
          UPDATE pms.appointments SET status='complete' WHERE id=102;
          UPDATE pms.appointments SET status='broken' WHERE id=103;
        SQL
      end
    end
    travel_to(TEST_NOW + 50.hours)
    Database.open { |db| db.transaction { ReminderFlow.new.run(1, send_reminders: false) } }
    get "/api/board?clinic=1"
    cases = json.fetch("cases")
    assert_equal "resolved", cases.find { |entry| entry["name"] == "Demo Patient 103" }.fetch("state")
    maya_case = cases.find { |entry| entry["name"] == "Demo Patient 102" }
    assert_equal "attention", maya_case.fetch("state")
    get "/api/work/#{maya_case.fetch('id')}"
    issues = json.fetch("issues")
    assert issues.find { |issue| issue["appointment_id"] == 102 }.fetch("resolved_at")
    refute issues.find { |issue| issue["appointment_id"] == 990102 }.fetch("resolved_at")
    assert_equal "Reply saved to message history.", send_reply(maya, "YES", "SMS")["message"]
  end

  def test_pms_reschedule_shapes_retire_old_visits_and_replies
    source_url = ENV.fetch("PMS_READER_URL")
    open_desk
    original = visits
    maya, noah = [102, 103].map { |id| original.find { |visit| visit["appointment_id"] == id } }
    maya_receipt = receipt_token(maya, "SMS")
    noah_receipt = receipt_token(noah, "Email")
    snapshot = pms_snapshot
    appointments = snapshot.fetch("appointments")
    moved = appointments.find { |appointment| appointment["id"] == 102 }
    moved["start_at"] = "2026-11-09T11:00:00"
    broken = appointments.find { |appointment| appointment["id"] == 103 }
    broken["status"] = "broken"
    appointments << broken.merge("id" => 990103, "status" => "scheduled", "start_at" => "2026-11-10T12:00:00")

    with_replica(snapshot) { run_reminders }
    assert_equal "Reply sent to Needs attention.", send_reply(maya, "YES", "SMS", token: maya_receipt)["message"]
    assert_equal "Reply saved to message history.", send_reply(noah, "YES", "Email", token: noah_receipt)["message"]
    Database.open do |db|
      obsolete = db.exec(<<~SQL).ntuples
        SELECT i.id FROM desk.issues i JOIN desk.visits v ON v.id=i.visit_id
        WHERE v.appointment_id IN (102,103) AND NOT v.current AND i.resolved_at IS NULL
      SQL
      assert_equal 0, obsolete
    end
    current = visits
    assert_nil current.find { |visit| visit["appointment_id"] == 103 }
    [102, 990103].each do |id|
      refute current.find { |visit| visit["appointment_id"] == id }.fetch("confirmed_at")
    end
  ensure
    ENV["PMS_READER_URL"] = source_url
  end

  def test_canceled_outcome_holds_reminders_while_replica_catches_up
    open_desk
    alex = visits.find { |visit| visit["appointment_id"] == 106 }
    send_reply(alex, "Please cancel.", "SMS")
    alex = visits.find { |visit| visit["appointment_id"] == 106 }
    path = "/api/work/#{alex.fetch('reply').fetch('case_id')}"
    get path
    send_json(path, outcome: "claim", version: json.fetch("case").fetch("version"))
    get path
    detail = json
    issue = detail.fetch("issues").find { |item| item["code"] == "ambiguous_reply" }
    send_json(path, outcome: "clarified", version: detail.fetch("case").fetch("version"),
              issue: issue["id"], appointment_ids: [106], note: "The patient clarified appointment 106.")
    get path
    clarified = json
    outcome_issue = clarified.fetch("issues").find do |item|
      item["appointment_id"] == 106 && item["code"] == "patient" && !item["resolved_at"] && !item["reply"]
    end
    send_json(path, outcome: "canceled", version: clarified.fetch("case").fetch("version"),
              issue: outcome_issue.fetch("id"), note: "Staff canceled in the PMS.")
    assert_match(/Awaiting PMS update/, visits.find { |visit| visit["appointment_id"] == 106 }.fetch("hold"))

    Database.open do |db|
      db.transaction do
        travel_to(TEST_NOW + 24.hours)
        flow = ReminderFlow.new
        visit_id = db.first_row("SELECT id FROM desk.visits WHERE appointment_id=$1 AND current", alex["appointment_id"]).fetch("id")
        before = db.first_row("SELECT count(*) n FROM desk.message_items WHERE visit_id=$1", visit_id)
        flow.run(1)
        assert_equal before, db.first_row("SELECT count(*) n FROM desk.message_items WHERE visit_id=$1", visit_id)
        assert_equal "scheduled", db.first_row("SELECT status FROM pms.appointments WHERE id=106").fetch("status")
      end
    end
    assert_equal "Reply sent to Needs attention.", send_reply(alex, "YES", "SMS")["message"]
    assert_nil visits.find { |visit| visit["appointment_id"] == 106 }["confirmed_at"]
  end

  def test_case_detail_agrees_with_calendar_after_a_decline
    open_desk
    visit = visits.find { |entry| entry["appointment_id"] == 103 }
    assert_equal "Appointment confirmed.", send_reply(visit, "YES", "Email")["message"]
    assert_equal "Reply sent to Needs attention.", send_reply(visit, "NO", "Email")["message"]
    get "/api/board?clinic=1"
    entry = json.fetch("cases").find { |row| row["name"] == "Demo Patient 103" }
    get "/api/work/#{entry.fetch('id')}"
    appointment = json.fetch("visits").find { |row| row["appointment_id"] == 103 }
    assert appointment.fetch("confirmed_at"), "the earlier confirmation stays in the record"
    assert appointment.fetch("reply"), "the case screen must carry the open reply review"
    assert appointment.fetch("declined_reply"), "the case screen must carry the NO reply"
    listing = visits.find { |row| row["appointment_id"] == 103 }
    get "/api/appointments?clinic=1&date=#{listing.fetch('start_at')[0, 10]}"
    calendar = json.fetch("visits").find { |row| row["appointment_id"] == 103 }
    assert calendar.fetch("reply")
    assert calendar.fetch("declined_reply")
  end

  def test_missing_source_row_is_not_counted_as_rescheduled
    open_desk
    snapshot = pms_snapshot
    clone = snapshot.fetch("appointments").find { |row| row["clinic_id"] == 1 && row["status"] == "scheduled" }
      .merge("id" => 990_201, "start_at" => "2026-11-20T12:00:00")
    with_replica(snapshot.merge("appointments" => snapshot.fetch("appointments") + [clone])) do
      PmsSnapshot.new.refresh
    end
    november = -> { OperationsQuery.call[:rows].find { |row| row["clinic_id"] == 1 && row["outcome_month"] == "2026-11" } }
    rescheduled_before = november.call.fetch("rescheduled")
    with_replica(snapshot) do
      PmsSnapshot.new.refresh
    end
    Database.open do |db|
      status = db.exec_params("SELECT status FROM pms.appointments WHERE id=$1", [990_201]).first.fetch("status")
      assert_equal "missing", status
      assert_equal "unknown", Appointment.find(990_201).outcome
      assert_equal rescheduled_before, november.call.fetch("rescheduled")
    end
  end
end

require_relative "test_helper"

class RefactorContractTest < Minitest::Test
  include Rack::Test::Methods

  def app = Rails.application

  def setup
    restore_demo_fixture
    get "/"
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
  end

  def enter(workspace, **options)
    post "/api/enter", JSON.generate(workspace: workspace, **options)
    assert last_response.ok?, last_response.body
  end

  def test_a_peer_changed_outside_the_current_calendar_prevents_auto_confirmation
    original = PmsReplica.read
    subject = Visit.current.find_by!(appointment_id: 106)
    receipt = subject.messages.sent.find_by!(channel: "SMS")
    peer = original.fetch("patients").find { |row| row.fetch("id") == 109 }
    peer.merge!("birthdate" => "1980-01-01", "wireless_phone" => " 1 (512) 555-0106 ")
    with_replica(original) { PmsSnapshot.new.refresh }
    assert ContactProfilesQuery.scope(1).exists?(id: 109)
    refute Appointment.for_clinic(1).where(patient_id: 109).exists?(start_at: TEST_NOW..)

    enter("patient")
    post "/api/patient/messages/#{receipt.token}", JSON.generate(body: "YES", key: "peer-source-change")
    assert last_response.ok?, last_response.body
    assert_equal "Reply sent to Needs attention.", JSON.parse(last_response.body).fetch("message")
    assert_nil subject.reload.confirmed_at
    assert FollowUpIssue.open.exists?(visit_id: subject.id, code: "ambiguous_reply")
    assert_equal " 1 (512) 555-0106 ", Patient.find(109).wireless_phone
    assert_equal "+15125550106", Patient.find(109).comparison_phone
  end

  def test_local_verification_and_guardian_permission_changes_keep_candidate_lookup_current
    snapshot = PmsReplica.read
    # The stock fixture deliberately shares 106's number with 107. Isolate the guardian rule.
    snapshot.fetch("patients").find { |row| row.fetch("id") == 107 }["wireless_phone"] = "512-555-0107"
    with_replica(snapshot) { PmsSnapshot.new.refresh }
    patient = Patient.find(109)
    staff = StaffMember.find(11)
    token = PatientDetailVerification.review_token(patient, "wireless_phone", nil)
    verification = PatientDetailVerification.record!(patient: patient, staff: staff,
      field: "wireless_phone", value: "512-555-0106", token: token)
    peers = -> { ContactProfilesQuery.sharing_destination(1, channel: "SMS", destination: "+15125550106", except: 106).map(&:id) }
    assert_includes peers.call, patient.id
    verification.update!(retired_at: TEST_NOW)
    refute_includes peers.call, patient.id

    guardian = Patient.find(190)
    token = PatientDetailVerification.review_token(guardian, "wireless_phone", nil)
    PatientDetailVerification.record!(patient: guardian, staff: staff,
      field: "wireless_phone", value: "512-555-0106", token: token)
    assert_includes peers.call, 161
    token = PatientDetailVerification.review_token(guardian, "email", nil)
    PatientDetailVerification.record!(patient: guardian, staff: staff,
      field: "email", value: "alex.106@example.test", token: token)
    # Email has a receipt-specific target. Old SMS receipts for 107 remain ambiguous.
    flow = ReminderFlow.new(now: TEST_NOW)
    subject = flow.load_visits(1, ids: [Visit.current.find_by!(appointment_id: 106).id]).sole
    flow.reminder_sender.deliver(visit: subject, channel: "Email", destination: "alex.106@example.test",
      purposes: ["courtesy"], recipient_id: 106)
    receipt = subject.messages.sent.find_by!(channel: "Email")
    enter("patient")
    post "/api/patient/messages/#{receipt.token}", JSON.generate(body: "YES", key: "verified-shared-guardian")
    assert last_response.ok?, last_response.body
    assert_equal "Reply sent to Needs attention.", JSON.parse(last_response.body).fetch("message")
    assert_nil subject.reload.confirmed_at
    ContactPermission.where(patient_id: 161, clinic_id: 1).update_all(authorized_guarantor_id: 191)
    refute_includes peers.call, 161
    # The authoritative policy still rejects an unrelated guardian link.
    visit = Visit.current.with_context.find_by!(appointment_id: 22)
    assert_nil ContactPolicy.new(TEST_NOW).for_visit(visit)
    post "/api/patient/messages/#{receipt.token}", JSON.generate(body: "YES", key: "guardian-permission-changed")
    assert last_response.ok?, last_response.body
    assert_equal "Appointment confirmed.", JSON.parse(last_response.body).fetch("message")
  end

  def test_history_pages_keep_source_precedence_and_moved_booking_order_without_duplicates
    enter("desk", clinic: 1, staff: 11)
    patient = Patient.find(103)
    ids = (7_100_000...7_100_060).to_a
    time = Time.utc(2030, 1, 10, 12)
    Appointment.insert_all!(ids.map { |id| { id: id, patient_id: patient.id, clinic_id: 1, start_at: time, status: "scheduled" } })
    moved = 7_100_100
    Appointment.insert_all!([{ id: moved, patient_id: patient.id, clinic_id: 5, start_at: time, status: "scheduled" }])
    Visit.insert_all!([time + 1.day, time - 1.day, time - 2.days].map do |at|
      { appointment_id: moved, patient_id: patient.id, clinic_id: 1, start_at: at,
        revision: "moved-#{at.to_i}", current: false }
    end)
    # A tracked time never overrides a source row still in this patient's clinic.
    Visit.insert_all!([{ appointment_id: ids.first, patient_id: patient.id, clinic_id: 1,
      start_at: time + 10.days, revision: "old-source-time", current: false }])
    AppointmentHistory.record_visits(Visit.where(appointment_id: [moved, ids.first]).to_a)

    found = []
    cursor = nil
    loop do
      get "/api/patient-details/103/history", **{ section: "appointments", filter: "upcoming", cursor: cursor }.compact
      assert last_response.ok?, last_response.body
      page = JSON.parse(last_response.body)
      assert_operator page.fetch("rows").length, :<=, 25
      found.concat(page.fetch("rows"))
      cursor = page.fetch("next_cursor")
      break unless cursor
    end
    assert_equal found.pluck("appointment_id").uniq, found.pluck("appointment_id")
    assert_equal [moved, *ids.reverse], found.first(61).pluck("appointment_id")
    # Paging uses the latest recorded time; the row retains the latest revision by ID.
    assert_equal (time - 2.days).strftime("%FT%T"), found.first.fetch("start_at").first(19)
    source = found.find { |row| row.fetch("appointment_id") == ids.first }
    assert_equal time.strftime("%FT%T"), source.fetch("start_at").first(19)
  end

  def test_activity_cursor_preserves_timestamp_type_and_id_ties
    enter("desk", clinic: 1, staff: 11)
    visit = Visit.current.find_by!(appointment_id: 103)
    stamp = TEST_NOW + 1.hour
    events = 30.times.map do |index|
      ActivityEvent.record(actor: "Patient", kind: "reply", body: "Tie #{index}", at: stamp, visit_id: visit.id)
    end
    received = []
    cursor = nil
    loop do
      get "/api/patient-details/103/history", **{ section: "activity", filter: "replies", cursor: cursor }.compact
      assert last_response.ok?, last_response.body
      page = JSON.parse(last_response.body)
      received.concat(page.fetch("rows").pluck("id"))
      cursor = page.fetch("next_cursor")
      break unless cursor
    end
    assert_equal events.reverse, received.first(30)
    assert_equal received.uniq, received
  end

  def test_reporting_matches_standard_time_at_both_dst_transitions
    enter("apex")
    [[Time.utc(2027, 3, 14, 8, 15), [1, 2, 3]],
     [Time.utc(2027, 11, 7, 6, 30), [0, 1, 2]],
     [Time.utc(2027, 11, 7, 7, 30), [0, 1, 2]]].each_with_index do |(now, hours), index|
      date = now.to_date
      ids = (7_200_000 + index * 3...7_200_003 + index * 3).to_a
      Appointment.insert_all!(ids.zip(hours).map do |id, hour|
        { id: id, patient_id: 103, clinic_id: 1, start_at: Time.utc(date.year, date.month, date.day, hour, 15), status: "scheduled" }
      end)
      # Diagnostic SQL is an independent oracle for the existing PostgreSQL semantics.
      expected = ApplicationRecord.connection.select_value(<<~SQL).to_i
        SELECT count(*) FROM pms.appointments WHERE clinic_id=1
        AND start_at >= '#{date.beginning_of_month}' AND start_at < '#{date.next_month.beginning_of_month}'
        AND start_at AT TIME ZONE 'America/Chicago' <= '#{now.iso8601}'
      SQL
      travel_to(now)
      get "/api/operations", month: date.strftime("%Y-%m")
      assert last_response.ok?, last_response.body
      row = JSON.parse(last_response.body).fetch("rows").find { |entry| entry.values_at("clinic_id", "outcome_month") == [1, date.strftime("%Y-%m")] }
      assert_equal expected, row.fetch("total")
      Appointment.where(id: ids).delete_all
    end
  end

  def test_follow_up_history_filters_and_pages_resolved_items
    enter("desk", clinic: 1, staff: 11)
    follow_up = FollowUpCase.find_by!(patient_id: 102, clinic_id: 1)
    ids = 30.times.map do |index|
      visit = Visit.create!(appointment_id: 7_300_000 + index, patient_id: 102, clinic_id: 1,
        revision: "history-#{index}", start_at: TEST_NOW, current: false)
      FollowUpIssue.create!(follow_up_case: follow_up, visit: visit, code: "patient", reason: "Handled reply",
        created_at: TEST_NOW + 1.hour, resolved_at: TEST_NOW + 2.hours).id
    end
    received = []
    cursor = nil
    loop do
      get "/api/patient-details/102/history", **{ section: "follow_up", filter: "resolved", cursor: cursor }.compact
      assert last_response.ok?, last_response.body
      page = JSON.parse(last_response.body)
      assert_operator page.fetch("rows").size, :<=, 25
      received.concat(page.fetch("rows").pluck("id"))
      cursor = page.fetch("next_cursor")
      break unless cursor
    end
    assert_equal ids.reverse, received.first(30)
    assert_equal received.uniq, received
  end
end

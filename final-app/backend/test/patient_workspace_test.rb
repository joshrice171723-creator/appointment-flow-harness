require_relative "test_helper"

class PatientWorkspaceTest < Minitest::Test
  include Rack::Test::Methods

  def app = Rails.application

  def setup
    restore_demo_fixture
    get "/"
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
    post "/api/enter", JSON.generate(workspace: "desk", clinic: 1, staff: 11)
    assert last_response.ok?
  end

  def test_both_entries_load_the_same_patient_workspace
    entry = FollowUpCase.for_clinic(1).where(patient_id: ContactProfilesQuery.scope(1).select(:id)).first!
    get "/api/board", clinic: 1
    assert last_response.ok?, last_response.body
    card = JSON.parse(last_response.body).fetch("cases").find { |row| row.fetch("id") == entry.id }
    assert_equal entry.patient_id, card.fetch("patient_id")

    get "/api/work/#{entry.id}"
    assert last_response.ok?, last_response.body
    from_case = JSON.parse(last_response.body)

    get "/api/patient-details/#{entry.patient_id}"
    assert last_response.ok?, last_response.body
    from_patient = JSON.parse(last_response.body)

    assert_equal entry.patient_id, from_patient.dig("person", "id")
    assert_equal entry.id, from_patient.dig("case", "id")
    assert_equal from_case.fetch("details"), from_patient.fetch("details")
    assert_equal from_case.fetch("issues"), from_patient.fetch("issues")
  end

  def test_history_pages_include_old_source_appointments_and_keep_cursor_in_scope
    appointment = Appointment.for_clinic(1).find(103)
    inserted_ids = (7_000_000...7_000_027).to_a
    Appointment.insert_all!(inserted_ids.map do |id|
      appointment.attributes.except("start_month").merge("id" => id, "start_at" => TEST_NOW - 40.days, "status" => "complete")
    end)

    path = "/api/patient-details/#{appointment.patient_id}/history"
    get path, section: "appointments", filter: "past"
    assert last_response.ok?, last_response.body
    page = JSON.parse(last_response.body)
    assert_equal 25, page.fetch("rows").size
    first_cursor = page.fetch("next_cursor")
    assert first_cursor
    ids = page.fetch("rows").pluck("appointment_id")
    while page["next_cursor"]
      get path, section: "appointments", filter: "past", cursor: page.fetch("next_cursor")
      assert last_response.ok?, last_response.body
      page = JSON.parse(last_response.body)
      ids.concat(page.fetch("rows").pluck("appointment_id"))
    end
    assert_equal ids.uniq, ids
    assert_empty inserted_ids - ids

    get path, section: "activity", cursor: first_cursor
    assert_equal 409, last_response.status

    outside = Appointment.for_clinic(5).where.not(patient_id: ContactProfilesQuery.scope(1).select(:id)).first!
    get "/api/patient-details/#{outside.patient_id}/history", section: "appointments"
    assert_equal 409, last_response.status
  end

  def test_receipt_lookup_keeps_the_recorded_destination_and_unmatched_reply
    message = Message.create!(clinic_id: 1, clinic_name: "Austin", patient_id: 103,
      recipient_id: 190, sender: "+15125550100", destination: "+17375550190",
      channel: "SMS", status: "sent", body: "Original reminder", token: SecureRandom.hex(16), created_at: TEST_NOW)
    ActivityEvent.record(actor: "Patient", kind: "late_reply", body: "Please call me.",
      message_id: message.id, at: TEST_NOW + 1.minute)

    get "/api/patient-details/103/history", section: "activity", message_id: message.id
    assert last_response.ok?, last_response.body
    reply, receipt = JSON.parse(last_response.body).fetch("rows")
    assert_equal ["event", "receipt"], [reply.fetch("entry_type"), receipt.fetch("entry_type")]
    assert_equal message.id, reply.fetch("message_id")
    assert_empty reply.fetch("appointment_ids")
    assert_equal "+17375550190", receipt.fetch("destination")
    assert_equal 190, receipt.fetch("recipient_id")

    get "/api/patient-details/104/history", section: "activity", message_id: message.id
    assert last_response.ok?, last_response.body
    assert_empty JSON.parse(last_response.body).fetch("rows")
  end

end

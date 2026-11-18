require_relative "test_helper"

class PatientDetailsTest < Minitest::Test
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

  def test_conflicting_pms_phone_blocks_delivery_until_staff_verifies_the_new_value
    patient_id = 104
    original = PmsReplica.read
    phone = detail(patient_id, "wireless_phone")
    assert_nil phone.fetch("pms_value")

    save_detail(patient_id, phone, "737-558-2104")
    assert last_response.ok?, last_response.body
    verification = PatientDetailVerification.active.find_by!(patient_id: patient_id, field: "wireless_phone")
    assert_equal 11, verification.staff_id
    assert_nil Patient.find(patient_id).wireless_phone
    assert_equal "+17375582104", Patient.find(patient_id).effective_detail("wireless_phone")
    token_before_change = detail(patient_id, "wireless_phone")

    with_replica(changed_patient(original, patient_id, "preferred_language" => "es")) { PmsSnapshot.new.refresh }
    assert_equal "+17375582104", Patient.find(patient_id).effective_detail("wireless_phone")
    refute verification.reload.conflicted_at

    changed = changed_patient(original, patient_id, "wireless_phone" => "737-558-2105")
    with_replica(changed) do
      save_detail(patient_id, token_before_change, "737-558-2104")
      assert_equal 409, last_response.status
      assert verification.reload.conflicted_at

      ReminderFlow.new(now: TEST_NOW).run(1)
      visit = Visit.current.find_by!(appointment_id: 104)
      assert_empty visit.messages
      assert FollowUpIssue.open.exists?(visit_id: visit.id, code: "contact",
        reason: ContactPolicy::HOLD_MESSAGES.fetch(:conflicting_details))

      latest = detail(patient_id, "wireless_phone")
      assert_equal "737-558-2105", latest.fetch("pms_value")
      assert_equal "+17375582104", latest.fetch("verified_value")
      assert latest.fetch("conflict")
      save_detail(patient_id, latest, latest.fetch("pms_value"))
      assert last_response.ok?, last_response.body
      accepted = PatientDetailVerification.active.find_by!(patient_id: patient_id, field: "wireless_phone")
      assert accepted.aligned_at
      refute accepted.conflicted_at
      assert verification.reload.retired_at

      OptOut.create!(clinic_id: 1, destination: "+17375582105")
      ReminderFlow.new(now: TEST_NOW).run(1)
      assert_empty visit.messages
      assert OptOut.exists?(clinic_id: 1, destination: "+17375582105")
    end
    assert_equal original, PmsReplica.read
  end

  def test_matching_pms_phone_uses_the_source_but_a_later_divergence_still_blocks_outreach
    patient_id = 104
    original = PmsReplica.read
    save_detail(patient_id, detail(patient_id, "wireless_phone"), "737-558-2104")
    assert last_response.ok?, last_response.body
    with_replica(changed_patient(original, patient_id, "wireless_phone" => "(737) 558-2104")) do
      PmsSnapshot.new.refresh
    end
    verification = PatientDetailVerification.find_by!(patient_id: patient_id, field: "wireless_phone")
    assert verification.aligned_at
    refute verification.conflicted_at
    assert_equal "(737) 558-2104", Patient.find(patient_id).effective_detail("wireless_phone")
    with_replica(changed_patient(original, patient_id, "wireless_phone" => "737-558-2105")) do
      PmsSnapshot.new.refresh
    end
    assert verification.reload.conflicted_at
  end

  def test_staff_cannot_verify_a_patient_outside_their_clinic
    patient_id = Appointment.for_clinic(5).first.patient_id
    refute ContactProfilesQuery.scope(1).exists?(id: patient_id)
    get "/api/patient-details/#{patient_id}"
    assert_equal 409, last_response.status
    post "/api/patient-details/#{patient_id}", JSON.generate(field: "birthdate", verified_value: "1990-01-01", token: "ignored")
    assert_equal 409, last_response.status
    refute PatientDetailVerification.exists?(patient_id: patient_id)
  end

  def test_blank_language_uses_english_and_an_explicit_unsupported_language_stays_on_hold
    snapshot = changed_patient(PmsReplica.read, 106, "preferred_language" => nil)
    with_replica(snapshot) do
      PmsSnapshot.new.refresh
      visit = Visit.current.with_context.find_by!(appointment_id: 106)
      policy = ContactPolicy.new(TEST_NOW)
      contact = policy.for_visit(visit)
      assert_nil policy.hold_code(visit, contact: contact)
      body = MessageTemplates.new.message_body(visit, "SMS", ["initial"], language: contact.language)
      assert_includes body, "Reply YES"

      save_detail(106, detail(106, "preferred_language"), "French")
      assert last_response.ok?, last_response.body
      visit = Visit.current.with_context.find_by!(appointment_id: 106)
      assert_equal "french", visit.patient.effective_detail("preferred_language")
      assert_equal :language, policy.hold_code(visit)
    end
  end

  private

  def detail(patient_id, field)
    get "/api/patient-details/#{patient_id}"
    assert last_response.ok?, last_response.body
    JSON.parse(last_response.body).fetch("details").find { |entry| entry.fetch("field") == field }
  end

  def save_detail(patient_id, field, value)
    post "/api/patient-details/#{patient_id}", JSON.generate(field: field.fetch("field"),
      verified_value: value, token: field.fetch("token"))
  end

  def changed_patient(snapshot, patient_id, values)
    patients = snapshot.fetch("patients").map do |patient|
      patient.fetch("id") == patient_id ? patient.merge(values) : patient
    end
    snapshot.merge("patients" => patients)
  end
end

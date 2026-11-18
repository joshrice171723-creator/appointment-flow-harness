require_relative "test_helper"

class ContactPolicyTest < Minitest::Test
  def test_minor_routes_only_to_the_authorized_adult
    guardian = Patient.new(id: 190, birthdate: Date.new(1980, 1, 1),
      wireless_phone: "(512) 555-0190", email: "guardian@example.test", preferred_language: "es")
    child = Patient.new(id: 161, birthdate: Date.new(2015, 1, 1), guarantor_id: guardian.id,
      wireless_phone: "(512) 555-0161", email: "child@example.test", preferred_language: "en")
    permission = ContactPermission.new(authorized_guarantor: guardian)
    policy = ContactPolicy.new(TEST_NOW)

    contact = policy.recipient(patient: child, permission: permission, timezone: "America/Chicago")
    assert_equal guardian.id, contact.id
    assert_equal "+15125550190", contact.phone
    assert_equal "guardian@example.test", contact.email
    assert_equal "es", contact.language

    permission.authorized_guarantor = nil
    assert_nil policy.recipient(patient: child, permission: permission, timezone: "America/Chicago")
    permission.authorized_guarantor = guardian
    child.guarantor_id = guardian.id + 1
    assert_nil policy.recipient(patient: child, permission: permission, timezone: "America/Chicago")
  end
end

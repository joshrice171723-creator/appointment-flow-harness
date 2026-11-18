require_relative "unit_test_helper"
require "uri"
require_relative "../app/services/contact_policy"

class ContactFormatTest < Minitest::Test
  def test_staff_entered_phone_formats
    policy = ContactPolicy.new(TEST_NOW)
    ["5125550102", "(512) 555-0102", "512.555.0102", "1-512-555-0102",
     " +1 (512) 555\u20110102 ", "512\u00a0555\u20130102"].each do |value|
      assert_equal "+15125550102", policy.phone(value), value.inspect
    end
    [nil, "", "555-0102", "Old number: 512-555-0102", "512-555-0102 x204",
     "512-555-0102 or 512-555-0103", "LQ nine five - 32", "+44 20 7946 0958",
     "(512 555-0102", "512/555/0102", "512\n555-0102"].each do |value|
      assert_nil policy.phone(value), value.inspect
    end
  end

  def test_staff_entered_email_formats
    policy = ContactPolicy.new(TEST_NOW)
    assert_equal "Pat.Smith+Visits@example.test", policy.address(" \tPat.Smith+Visits@EXAMPLE.TEST\u00a0")
    [nil, "", "Pat Smith <pat@example.test>", "pat@example.test; other@example.test",
     "pat..smith@example.test", ".pat@example.test", "pat@-example.test", "pat@example", "pat@example.test\n"].each do |value|
      assert_nil policy.address(value), value.inspect
    end
  end
end

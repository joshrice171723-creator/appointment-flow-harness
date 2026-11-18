require_relative "test_helper"

class PmsTimestampTest < Minitest::Test
  def setup
    restore_demo_fixture
  end

  def test_source_text_preserves_seconds_fraction_and_stored_fields_in_another_display_zone
    time = Time.utc(2026, 11, 5, 12, 4, 3, 123456)
    assert_equal "2026-11-05T12:04:03.123456", PmsTimestamp.text(time)
    assert_equal "2026-11-05T12:04:03", PmsTimestamp.text(time.change(usec: 0))
    Time.use_zone("America/Chicago") do
      assert_equal "2026-11-05T12:04:03.123456", PmsTimestamp.text(time.in_time_zone)
    end
    offset_time = time.getlocal("-06:00")
    assert_equal "2026-11-05T12:04:03.123456", PmsTimestamp.text(offset_time)
    assert_equal(-21_600, offset_time.utc_offset)
  end

  def test_confirmation_digest_keeps_its_original_timestamp_format
    appointment = Appointment.new(id: 999, patient_id: 102, clinic_id: 1,
      start_at: Time.utc(2026, 11, 5, 12, 4, 3, 123456), status: "scheduled")
    expected = Digest::SHA256.hexdigest("999|102|1|2026-11-05 12:04:03.123456|scheduled")
    assert_equal expected, appointment.confirmation_revision
  end

  def test_stored_wall_time_and_clinic_conversion_ignore_the_display_zone
    appointment = Appointment.find(102)
    visit = Visit.current.with_context.find_by!(appointment_id: 102)
    fields = ->(time) { [time.year, time.month, time.day, time.hour, time.min, time.sec] }
    expected_fields = fields.call(appointment.start_at)
    expected_instant = visit.starts_at_utc
    Time.use_zone("Pacific/Honolulu") do
      assert_equal expected_fields, fields.call(Appointment.find(102).start_at)
      assert_equal expected_instant, Visit.with_context.find(visit.id).starts_at_utc
    end
  end
end

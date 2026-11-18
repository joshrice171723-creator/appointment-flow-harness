require_relative "test_helper"

class RefactorRestoreTest < Minitest::Test
  self.committed_demo_tests = %w[test_committed_fixture_restores_generated_values_and_projections]

  def test_committed_fixture_restores_generated_values_and_projections
    Minitest::Test.demo_fixture_dirty = true
    restore_demo_fixture
    assert AppointmentHistory.exists?
    assert_equal Date.new(2026, 11, 1), Appointment.find(102).start_month
    assert_equal "+15125550106", Patient.find(106).comparison_phone
    assert Visit.current.exists?(appointment_id: 106)
  end
end

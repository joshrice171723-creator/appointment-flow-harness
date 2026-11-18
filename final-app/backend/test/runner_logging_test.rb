ENV["RAILS_ENV"] = "test"
require_relative "unit_test_helper"
require_relative "../config/environment"
require "stringio"

class RunnerLoggingTest < Minitest::Test
  def test_failure_logs_location_without_exception_payload
    original_logger = Rails.logger
    output = StringIO.new
    error = RuntimeError.new("Private patient reply and SQL parameters")
    error.set_backtrace(["reminder_flow.rb:184:in 'deliver'"])

    Rails.logger = Logger.new(output)
    ReminderRunner.log_failure(error, context: "Reminder work failed for clinic 994")

    assert_includes output.string, "clinic 994: RuntimeError"
    assert_includes output.string, "reminder_flow.rb:184"
    refute_includes output.string, error.message
  ensure
    Rails.logger = original_logger
  end
end

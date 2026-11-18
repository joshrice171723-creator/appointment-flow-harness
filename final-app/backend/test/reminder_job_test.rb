require_relative "test_helper"
require "stringio"

class ReminderJobTest < Minitest::Test
  self.committed_demo_tests = %w[test_failed_batch_can_be_retried_without_duplicate_delivery]

  def setup
    restore_demo_fixture
  end

  def test_repeated_job_does_not_repeat_daily_deliveries
    ClinicSetting.update_all(last_reminder_on: nil)
    ReminderJob.new.perform
    counts = [Message.count, MessageItem.count]
    dates = ClinicSetting.order(:clinic_id).pluck(:last_reminder_on)
    ReminderJob.new.perform
    assert_equal counts, [Message.count, MessageItem.count]
    assert_equal dates, ClinicSetting.order(:clinic_id).pluck(:last_reminder_on)
    assert_includes dates, TEST_NOW.to_date
  end

  def test_source_failure_reaches_sidekiq_without_sending_or_exposing_payload
    original_read = PmsReplica.method(:read)
    original_logger = Rails.logger
    output = StringIO.new
    Rails.logger = Logger.new(output)
    PmsReplica.define_singleton_method(:read) { |**| raise ReminderFlow::Conflict, "private patient payload" }
    ClinicSetting.update_all(last_reminder_on: nil)
    before = [Message.count, SourceSync.first.last_synced_at]
    failure = assert_raises(ReminderJob::Failure) { ReminderJob.new.perform }
    assert_equal before, [Message.count, SourceSync.first.last_synced_at]
    assert ClinicSetting.where.not(last_reminder_on: nil).empty?
    assert_nil failure.cause
    refute_includes failure.message, "private patient payload"
    refute_includes output.string, "private patient payload"
    assert_includes output.string, "PMS refresh"
  ensure
    PmsReplica.define_singleton_method(:read, original_read)
    Rails.logger = original_logger
  end

  def test_failed_batch_can_be_retried_without_duplicate_delivery
    original_send = ReminderSender.instance_method(:call)
    SourceSync.update_all(last_synced_at: Time.utc(2000))
    ClinicSetting.update_all(last_reminder_on: nil)
    ReminderSender.define_method(:call) do |**options|
      original_send.bind_call(self, **options)
      raise "failure after batch writes"
    end
    before = Message.count
    assert_raises(ReminderJob::Failure) { ReminderJob.new.perform }
    assert_equal before, Message.count
    refute SourceSync.status.fetch("stale"), "The successful refresh must survive batch rollback."
    assert ClinicSetting.where.not(last_reminder_on: nil).empty?
    ReminderSender.define_method(:call, original_send)
    ReminderJob.new.perform
    after = Message.count
    ReminderJob.new.perform
    assert_equal after, Message.count
    assert_includes ClinicSetting.pluck(:last_reminder_on), TEST_NOW.to_date
  ensure
    ReminderSender.define_method(:call, original_send)
  end
end

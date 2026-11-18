class ReminderJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  class Failure < StandardError; end

  def perform
    ReminderRunner.tick
  rescue StandardError => error
    ReminderRunner.log_failure(error, context: "Reminder job")
    # Sidekiq persists errors; keep patient text and SQL values out of Redis.
    raise Failure, "Reminder tick failed (#{error.class}). See worker logs.", cause: nil
  end
end

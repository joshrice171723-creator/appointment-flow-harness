Sidekiq.configure_server do |config|
  config.on(:startup) { ReminderJob.perform_async }
end

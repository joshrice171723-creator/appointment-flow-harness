class ReminderRunner
  class Failure < StandardError; end

  def self.tick
    failed = false
    flow = ReminderFlow.new
    batches = flow.due_batches.to_h
    refreshed = true
    begin
      PmsSnapshot.new.refresh
    rescue ReminderFlow::Conflict => error
      refreshed = false
      failed = true
      log_failure(error, context: "PMS refresh")
    end

    Clinic.messaging_enabled.each do |clinic|
      id = clinic.id
      begin
        clinic_flow = ReminderFlow.new
        if refreshed && batches.key?(id)
          clinic_flow.run_daily_batch(id, batches.fetch(id))
        else
          clinic_flow.run(id, send_reminders: false)
        end
      rescue StandardError => error
        failed = true
        log_failure(error, context: "Reminder work failed for clinic #{id}")
      end
    end
    raise Failure, "One or more reminder operations failed." if failed
  end

  def self.log_failure(error, context:)
    # Exception messages can contain SQL values or patient text. Locations are safe diagnostics.
    cause = error.cause
    summary = "#{context}: #{error.class}"
    summary += " (caused by #{cause.class})" if cause
    Rails.logger.error([summary, *Array(error.backtrace).first(8)].join("\n"))
  end
end

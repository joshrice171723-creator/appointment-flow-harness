class ReminderFlow
  # Source timestamps are clinic-local; these bounds include the UTC date offset.
  REMINDER_LOOKBACK_DAYS = 1
  REMINDER_LOOKAHEAD_DAYS = 9
  class Conflict < StandardError; end

  class FakeSender
    def deliver(channel:, destination:, body:, key:)
      ["sent", "fake-#{key}"]
    end
  end

  def initialize(sender: FakeSender.new, now: nil)
    @sender = sender
    @now = now
  end

  def now
    @now ||= Time.current
  end

  def load_visits(clinic, current: true, ids: nil, patient_id: nil, days: nil)
    records = Visit.for_clinic(clinic).with_messaging_context
    records = records.current if current
    records = records.where(id: ids) unless ids.nil?
    records = records.for_patient(patient_id) unless patient_id.nil?
    records = records.within_window(days.begin, days.end) if days

    records.chronological.to_a
  end

  def contact_policy
    @contact_policy ||= ContactPolicy.new(now)
  end

  def message_templates
    @message_templates ||= MessageTemplates.new
  end

  def follow_ups
    @follow_ups ||= FollowUpWorkflow.new(now: now)
  end

  def reminder_sender
    @reminder_sender ||= ReminderSender.new(
      transport: @sender, now: now, contact_policy: contact_policy,
      message_templates: message_templates, follow_ups: follow_ups
    )
  end

  def due_batches
    ClinicSetting.order(:clinic_id).filter_map do |setting|
      zone = Time.find_zone(setting.timezone)
      next unless zone

      local_time = now.in_time_zone(zone)
      today = local_time.to_date
      already_ran = setting.last_reminder_on && setting.last_reminder_on >= today
      [setting.clinic_id, today] if ReminderSchedule::SEND_HOURS.cover?(local_time.hour) && !already_ran
    end
  end

  # The daily marker and all fake deliveries succeed or roll back together.
  def run_daily_batch(clinic_id, day)
    ApplicationRecord.transaction do
      Database.lock_clinic(clinic_id)
      settings = ClinicSetting.where(clinic_id: clinic_id)
      due = settings.where(last_reminder_on: nil).or(settings.where(last_reminder_on: ...day))
      next 0 if due.update_all(last_reminder_on: day).zero?

      count = process_clinic(clinic_id, send_reminders: true)
      raise Conflict, "Refresh the PMS before running reminders." if SourceSync.status["stale"]

      count
    end
  end

  def run(clinic_id, send_reminders: true)
    ApplicationRecord.transaction do
      Database.lock_clinic(clinic_id)
      process_clinic(clinic_id, send_reminders: send_reminders)
    end
  end

  private

  def process_clinic(clinic_id, send_reminders:)
    ReconcileAppointments.new(now: now).for_clinic(clinic_id)
    today = now.utc.to_date
    current_visits = load_visits(clinic_id, days: (today - REMINDER_LOOKBACK_DAYS)...(today + REMINDER_LOOKAHEAD_DAYS))
    return 0 if current_visits.empty? || SourceSync.status["stale"]

    reminder_sender.call(visits: current_visits, clinic_id: clinic_id, send_reminders: send_reminders)
  end
end

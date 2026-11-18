class ReminderSchedule
  SEND_HOURS = (10...18).freeze
  REMINDER_HOUR = SEND_HOURS.begin
  INITIAL_DAYS_BEFORE = 7
  BACKUP_DAYS_BEFORE = 6
  FOLLOW_UP_DAYS_BEFORE = 3
  FINAL_DAYS_BEFORE = 1
  RECENT_AGREEMENT_WINDOW = (0..72.hours).freeze

  # attempts_by_purpose maps purpose strings to Message records, including failed attempts.
  # Missing key means never attempted; responded includes handled replies and opt-outs.
  def initialize(visit:, now:, attempts_by_purpose:, responded:, email_available:)
    @visit = visit
    @now = now
    @attempts_by_purpose = attempts_by_purpose
    @responded = responded
    @email_available = email_available
  end

  # Returns due purpose strings, or [] when none are due/in the local send window.
  def purposes
    return [] unless within_send_hours?

    purposes = []
    purposes << "initial" if initial_request_due?
    purposes << "backup" if email_backup_due?
    purposes << "follow_up" if follow_up_due?
    purposes << "courtesy" if day_before_reminder_due?
    purposes
  end

  private

  def within_send_hours?
    SEND_HOURS.cover?(@now.in_time_zone(@visit.timezone).hour)
  end

  def initial_attempt
    @attempts_by_purpose["initial"]
  end

  def initial_on_prior_day?
    initial_attempt && initial_attempt.created_at.in_time_zone(@visit.timezone).to_date <
      @now.in_time_zone(@visit.timezone).to_date
  end

  def recently_agreed?
    @visit.agreed_at && RECENT_AGREEMENT_WINDOW.cover?(@visit.starts_at_utc - @visit.agreed_at)
  end

  def initial_request_due?
    !initial_attempt && !recently_agreed? && !@visit.confirmed_at
  end

  def unanswered_after_initial?
    initial_on_prior_day? && !@visit.confirmed_at && !@responded
  end

  def email_backup_due?
    unanswered_after_initial? && initial_attempt.channel == "SMS" &&
      @email_available && !@attempts_by_purpose["backup"] &&
      @now >= @visit.reminder_at(days_before: BACKUP_DAYS_BEFORE) &&
      @now < @visit.reminder_at(days_before: FOLLOW_UP_DAYS_BEFORE)
  end

  def follow_up_due?
    unanswered_after_initial? && !@attempts_by_purpose["follow_up"] &&
      @now >= @visit.reminder_at(days_before: FOLLOW_UP_DAYS_BEFORE)
  end

  def day_before_reminder_due?
    reminder_at = @visit.reminder_at(days_before: FINAL_DAYS_BEFORE)
    agreed_after_reminder_time = recently_agreed? && @visit.agreed_at >= reminder_at
    @now >= reminder_at && !@attempts_by_purpose["courtesy"] &&
      (!initial_attempt || initial_on_prior_day?) && !agreed_after_reminder_time
  end
end

class Visit < ApplicationRecord
  self.table_name = "desk.visits"
  self.skip_time_zone_conversion_for_attributes = [:start_at]
  belongs_to :appointment, optional: true
  belongs_to :clinic
  belongs_to :clinic_setting, foreign_key: :clinic_id, primary_key: :clinic_id
  belongs_to :patient, optional: true
  belongs_to :contact_permission, foreign_key: [:patient_id, :clinic_id],
    primary_key: [:patient_id, :clinic_id], optional: true
  has_many :message_items
  has_many :messages, through: :message_items
  has_many :events, class_name: "ActivityEvent"
  has_many :issues, class_name: "FollowUpIssue"
  after_create { AppointmentHistory.record_visits([self]) }

  scope :with_context, -> {
    includes(:appointment, :clinic, :clinic_setting, patient: :active_detail_verifications,
             contact_permission: { authorized_guarantor: :active_detail_verifications })
  }

  delegate :timezone, :sender, to: :clinic_setting

  scope :current, -> { where(current: true) }
  scope :for_clinic, ->(id) { where(clinic_id: id) }

  scope :for_patient, ->(id) { where(patient_id: id) }
  scope :within_window, ->(first, last) { where(start_at: first...last) }
  scope :chronological, -> { order(:start_at, :id) }
  scope :with_messaging_context, -> { joins(:clinic, :clinic_setting).with_context }
  scope :with_pending_pms_change, -> { where(id: ActivityEvent.pms_change.select(:visit_id)) }

  def matches_appointment?(source)
    source && patient_id == source.patient_id && clinic_id == source.clinic_id && start_at == source.start_at
  end

  def patient_name
    patient&.display_name || "Patient mapping needs review"
  end

  def provider_name
    appointment.provider_name if matches_appointment?(appointment)
  end

  def latest_patient_reply
    events.select { |event| event.actor == "Patient" && event.kind == "reply" }.max_by(&:id)
  end

  def sms_permitted?
    patient.present? && contact_permission&.sms == true
  end

  def email_permitted?
    patient.present? && contact_permission&.email == true
  end

  def self.clinic_wall_time_to_utc(time, timezone)
    local = Time.utc(time.year, time.month, time.day, time.hour, time.min, time.sec)
    TZInfo::Timezone.get(timezone).local_to_utc(local)
  rescue TZInfo::InvalidTimezoneIdentifier, TZInfo::PeriodNotFound, TZInfo::AmbiguousTime
    nil
  end

  # `start_at` is the stored clinic wall time; this is the same instant in UTC.
  def starts_at_utc
    self.class.clinic_wall_time_to_utc(start_at, timezone)
  end

  def reminder_at(days_before:)
    day = start_at.to_date - days_before
    self.class.clinic_wall_time_to_utc(Time.utc(day.year, day.month, day.day, ReminderSchedule::REMINDER_HOUR), timezone)
  end

  def pending_pms_change?
    events.pms_change.exists?
  end

  def current_reply_target?(now:, source: Appointment.find_by(id: appointment_id))
    return false unless patient && source&.status == "scheduled"
    return false unless source.confirmation_revision == revision

    starts_at_utc.nil? || starts_at_utc > now
  end

  def current_scheduled_revision?
    source = Appointment.find_by(id: appointment_id)
    source&.status == "scheduled" && source.confirmation_revision == revision
  end

  def upcoming_on_open_day?(at)
    starts_at_utc && starts_at_utc > at && !start_at.sunday?
  end

  def confirmable_at?(at)
    patient && current && current_scheduled_revision? &&
      upcoming_on_open_day?(at) && !pending_pms_change?
  end

  def confirm!(actor:, at:, agreement: false)
    with_lock do
      unless confirmable_at?(at)
        raise ReminderFlow::Conflict, "The appointment changed or is no longer available. Review it before confirming."
      end

      self.confirmed_at ||= at
      self.confirmed_by ||= actor
      self.agreed_at = at if agreement
      save!
    end
  end
end

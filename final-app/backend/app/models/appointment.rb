require "digest"

class Appointment < PmsRecord
  self.table_name = "pms.appointments"
  # PMS timestamps are wall-clock fields, independent of the Rails display zone.
  self.skip_time_zone_conversion_for_attributes = [:start_at, :updated_at]
  RECONCILIATION_LOOKBACK = 2.days
  RECONCILIATION_LOOKAHEAD = 15.days
  OUTCOMES = { "complete" => "completed", "broken" => "rescheduled", "unscheduled" => "canceled" }.freeze

  belongs_to :patient
  belongs_to :clinic
  belongs_to :contact_permission, foreign_key: [:patient_id, :clinic_id],
    primary_key: [:patient_id, :clinic_id], optional: true
  has_many :visits
  has_one :current_visit, -> { current }, class_name: "Visit"

  scope :for_clinic, ->(id) { where(clinic_id: id) }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :within_window, ->(first, last) { where(start_at: first...last) }
  scope :chronological, -> { order(:start_at, :id) }

  def self.needing_reconciliation(clinic_id, now:, appointment_ids: nil)
    first = (now - RECONCILIATION_LOOKBACK).change(usec: 0)
    last = (now + RECONCILIATION_LOOKAHEAD).change(usec: 0)
    upcoming = for_clinic(clinic_id).scheduled.within_window(first, last)
    tracked = where(id: Visit.current.for_clinic(clinic_id).pluck(:appointment_id))
    candidates = upcoming.or(tracked)
    candidates = candidates.where(id: appointment_ids) if appointment_ids
    candidates.includes(:current_visit).order(:id).select do |appointment|
      visit = appointment.current_visit
      visit.nil? || appointment.status != "scheduled" || !visit.matches_appointment?(appointment)
    end
  end

  # Only these source fields invalidate a previous confirmation.
  def confirmation_revision
    values = [id, patient_id, clinic_id, start_at, status].map do |value|
      if value.is_a?(Time)
        PmsTimestamp.text(value, separator: " ")
      else
        value.nil? ? "None" : value.to_s
      end
    end
    Digest::SHA256.hexdigest(values.join("|"))
  end

  def outcome
    OUTCOMES.fetch(status, "unknown")
  end
end

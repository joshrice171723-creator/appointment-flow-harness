# One latest tracked time per booking, patient, and clinic. Source rows take precedence in reads.
class AppointmentHistory < ApplicationRecord
  self.table_name = "desk.appointment_histories"
  self.skip_time_zone_conversion_for_attributes = [:start_at]
  self.primary_key = [:appointment_id, :patient_id, :clinic_id]

  def self.record_visits(visits)
    dates = visits.group_by { |visit| [visit.appointment_id, visit.patient_id, visit.clinic_id] }
      .transform_values { |versions| versions.map(&:start_at).max }
    return if dates.empty?

    existing = where([:appointment_id, :patient_id, :clinic_id] => dates.keys)
      .pluck(:appointment_id, :patient_id, :clinic_id, :start_at)
      .to_h { |appointment, patient, clinic, time| [[appointment, patient, clinic], time] }
    rows = dates.filter_map do |(appointment, patient, clinic), time|
      previous = existing[[appointment, patient, clinic]]
      next if previous && previous >= time
      { appointment_id: appointment, patient_id: patient, clinic_id: clinic, start_at: time }
    end
    upsert_all(rows, returning: false) if rows.any?
  end
end

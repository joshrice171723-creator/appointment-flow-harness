# Assessment-only patients and replay. The runtime PMS reader remains SELECT-only.
class AssessmentPatientDetails
  SOURCE_NOTES = ["Assessment details: missing birthdate", "Assessment details: changed phone"].freeze

  def self.seed_replica(now:, clinics:)
    ReplicaSeed::Record.transaction do
      clinics.each do |clinic|
        clinic_id = clinic.fetch("id")
        day = now.in_time_zone(clinic.fetch("timezone")).to_date + 2
        day += 1 if day.sunday?
        SOURCE_NOTES.each_with_index do |note, offset|
          next if ReplicaSeed::Appointment.exists?(clinic_id: clinic_id, procedure_note: note)

          id = ReplicaSeed::Patient.maximum(:id).to_i + 1

          ReplicaSeed::Patient.create!(id: id, **ReplicaSeed.patient_name(id),
            birthdate: (Date.new(1988, 1, 1) if offset == 1),
            wireless_phone: source_phone(id), preferred_language: "en")
          start_at = Time.utc(day.year, day.month, day.day, 14 + offset)
          ReplicaSeed::Appointment.create!(id: ReplicaSeed::Appointment.maximum(:id).to_i + 1,
            patient_id: id, clinic_id: clinic_id, procedure_note: note,
            start_at: start_at, length_minutes: 30, status: "scheduled",
            provider_name: "Dr. Jordan Patel", updated_at: start_at - 7.days)
        end
      end
    end
  end

  def self.source_phone(id)
    format("(737) 558-%04d", id % 10_000)
  end

  def initialize(now:, source_snapshot:)
    @now = now
    @source_snapshot = source_snapshot
  end

  # Called by db:seed under the app transaction and exclusive snapshot lock.
  def replay
    ClinicSetting.find_each do |setting|
      staff = StaffMember.where(clinic_id: setting.clinic_id).order(:id).first
      next unless staff

      birthdate_appointment = unseeded_appointment(SOURCE_NOTES.first, setting)
      conflict_appointment = unseeded_appointment(SOURCE_NOTES.last, setting)
      verify_birthdate(birthdate_appointment, staff, setting) if birthdate_appointment
      replay_phone_conflict(conflict_appointment, staff, setting) if conflict_appointment
    end
  end

  private

  def unseeded_appointment(note, setting)
    appointment = Appointment.scheduled.for_clinic(setting.clinic_id).find_by(procedure_note: note)
    return if appointment && PatientDetailVerification.exists?(patient_id: appointment.patient_id)

    appointment if appointment && Visit.clinic_wall_time_to_utc(appointment.start_at, setting.timezone) > @now
  end

  def verify_birthdate(appointment, staff, setting)
    at = example_send_time(setting)
    reconcile(appointment, at)
    run_reminders(appointment, at: at, send_reminders: false)
    verify(appointment.patient_id, staff, field: "birthdate", value: "1988-03-21", at: at + 10.minutes)
    run_reminders(appointment, at: at + 15.minutes, send_reminders: true)
    visit = Visit.current.find_by!(appointment_id: appointment.id)
    unless visit.messages.sent.exists? && FollowUpIssue.where(visit: visit, code: "contact").where.not(resolved_at: nil).exists?
      raise ReminderFlow::Conflict, "The birthdate example did not clear its hold and send."
    end
  end

  def replay_phone_conflict(appointment, staff, setting)
    at = example_send_time(setting)
    earlier_patients = @source_snapshot.fetch("patients").map do |row|
      row.fetch("id") == appointment.patient_id ? row.merge("wireless_phone" => nil) : row
    end
    earlier_snapshot = @source_snapshot.merge("patients" => earlier_patients)
    PmsSnapshot.new(read_snapshot: -> { earlier_snapshot }).refresh
    verify(appointment.patient_id, staff, field: "wireless_phone",
      value: format("(737) 559-%04d", appointment.patient_id % 10_000), at: at + 10.minutes)
    PmsSnapshot.new(read_snapshot: -> { @source_snapshot }).refresh(observed_at: at + 12.minutes)
    reconcile(appointment, at)
    run_reminders(appointment, at: at + 15.minutes, send_reminders: true)
    visit = Visit.current.find_by!(appointment_id: appointment.id)
    unless !visit.messages.exists? && FollowUpIssue.open.exists?(visit_id: visit.id, code: "contact",
      reason: ContactPolicy::HOLD_MESSAGES.fetch(:conflicting_details))
      raise ReminderFlow::Conflict, "The conflicting phone example did not block reminders."
    end
  end

  def verify(patient_id, staff, field:, value:, at:)
    patient = Patient.find(patient_id)
    token = PatientDetailVerification.review_token(patient, field, nil)
    PatientDetailVerification.record!(patient: patient, staff: staff, field: field, value: value, token: token, at: at)
  end

  def reconcile(appointment, at)
    ReconcileAppointments.new(now: at).reconcile_appointment(appointment, clinic_id: appointment.clinic_id)
  end

  def run_reminders(appointment, at:, send_reminders:)
    visits = Visit.current.where(appointment_id: appointment.id).with_context.to_a
    ReminderFlow.new(now: at).reminder_sender.call(visits: visits, clinic_id: appointment.clinic_id,
      send_reminders: send_reminders)
  end

  def example_send_time(setting)
    local_now = @now.in_time_zone(setting.timezone)
    at = local_now.change(hour: ReminderSchedule::REMINDER_HOUR, min: 0, sec: 0, usec: 0)
    at > local_now - 20.minutes ? at - 1.day : at
  end
end

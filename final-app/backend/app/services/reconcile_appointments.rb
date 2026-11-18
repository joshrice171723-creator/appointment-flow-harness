class ReconcileAppointments
  def initialize(now:)
    @now = now
    @follow_ups = FollowUpWorkflow.new(now: now)
  end

  # The caller holds the clinic lock until its related writes commit.
  def for_clinic(clinic_id)
    @follow_ups.resolve_finished_follow_ups(clinic_id)
    appointments = Appointment.needing_reconciliation(clinic_id, now: @now)
    reconcile_appointments(appointments, clinic_id: clinic_id)
    nil
  end

  def for_case(follow_up)
    clinic_id = follow_up.clinic_id
    @follow_ups.resolve_finished_follow_ups(clinic_id, case_id: follow_up.id)
    clinic_visits = Visit.for_clinic(clinic_id)
    affected_visits = clinic_visits.where(id: follow_up.issues.select(:visit_id))
      .or(clinic_visits.current.for_patient(follow_up.patient_id))
    appointments = Appointment.needing_reconciliation(clinic_id, now: @now, appointment_ids: affected_visits.select(:appointment_id))
    reconcile_appointments(appointments, clinic_id: clinic_id)
    nil
  end

  # The caller holds the clinic lock or the exclusive snapshot lock.
  def reconcile_appointment(appointment, clinic_id:)
    Database.lock_appointment(appointment.id)
    previous_visit = Visit.current.find_by(appointment_id: appointment.id)
    replacement = retire_changed_visit_and_build_replacement(appointment, previous_visit, clinic_id: clinic_id)
    replacement&.tap(&:save!)
  end

  private

  def reconcile_appointments(appointments, clinic_id:)
    return if appointments.empty?

    Database.lock_appointments(appointments.map(&:id))
    current_visits = Visit.current.where(appointment_id: appointments.map(&:id)).index_by(&:appointment_id)
    replacements = appointments.filter_map do |appointment|
      retire_changed_visit_and_build_replacement(appointment, current_visits[appointment.id], clinic_id: clinic_id)
    end
    return if replacements.empty?

    ActiveRecord::Associations::Preloader.new(records: replacements, associations: [:clinic, :clinic_setting]).call
    replacements.each(&:validate!)
    # These cache projections have no save callbacks; keep validation and database constraints.
    rows = replacements.map { |visit| visit.attributes.except("id", "start_month") }
    Visit.insert_all!(rows, returning: false)
    AppointmentHistory.record_visits(replacements)
  end

  def retire_changed_visit_and_build_replacement(appointment, previous_visit, clinic_id:)
    revision = appointment.confirmation_revision

    if previous_visit && (previous_visit.revision != revision || appointment.status != "scheduled")
      previous_visit.update!(current: false)
      @follow_ups.close_visit_follow_ups(previous_visit, "The PMS changed or removed this appointment time.")
      previous_visit = nil
    end
    return if previous_visit || appointment.status != "scheduled" || appointment.clinic_id != clinic_id

    Visit.new(
      appointment_id: appointment.id, patient_id: appointment.patient_id,
      clinic_id: clinic_id, revision: revision, start_at: appointment.start_at
    )
  end
end

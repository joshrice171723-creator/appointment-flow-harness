class DeskController < ApplicationController
  def appointments
    staff, clinic = staff_scope
    zone = Time.find_zone(clinic.setting.timezone) || "UTC"
    today = Time.current.in_time_zone(zone).to_date
    date = calendar_date(today) if params.key?(:date)
    visits = AppointmentsQuery.new(clinic, date: date).call
    render json: { staff: staff.attributes, clinic: ClinicSerializer.as_json(clinic), visits: visits,
      today: today, date: date, week: date&.beginning_of_week, sync_status: SourceSync.status }
  end

  def board
    staff, clinic = staff_scope
    render json: { staff: staff.attributes, clinic: ClinicSerializer.as_json(clinic),
      cases: BoardQuery.call(clinic.id), now: Time.current, sync_status: SourceSync.status }
  end

  def case_detail
    entry, staff, clinic = scoped_case
    render json: CaseDetailQuery.call(entry, staff, clinic)
  end

  def patient_details
    staff, clinic = staff_scope
    patient = scoped_patient(clinic.id)
    entry = FollowUpCase.for_clinic(clinic.id).includes(:owner).find_by(patient_id: patient.id)
    render json: CaseDetailQuery.call(entry, staff, clinic, patient: patient)
  end

  def patient_history
    _, clinic = staff_scope
    patient = scoped_patient(clinic.id)
    filters = params.permit(:section, :filter, :cursor, :appointment_id, :message_id)
    render json: PatientWorkspaceHistory.new(patient, clinic).call(**filters.to_h.symbolize_keys)
  end

  def verify_patient_detail
    _, clinic = staff_scope
    fields = params.permit(:field, :verified_value, :token, :originating_patient_id)
    unless PatientDetailVerification::FIELDS.key?(fields[:field]) &&
           fields[:verified_value].is_a?(String) && fields[:verified_value].present? &&
           fields[:verified_value].bytesize <= 254 && fields[:token].to_s.match?(/\A[0-9a-f]{64}\z/)
      raise ReminderFlow::Conflict, "Choose a detail and enter a value to verify."
    end
    verification_patient(clinic, fields)
    PmsSnapshot.new.refresh

    ApplicationRecord.transaction do
      Database.lock_snapshot
      staff, clinic = staff_scope(clinic_id: clinic.id)
      patient = verification_patient(clinic, fields)
      PatientDetailVerification.record!(patient: patient, staff: staff, field: fields[:field],
        value: fields[:verified_value], token: fields[:token])
    end
    render json: { message: "Patient detail verified in Appointment Flow." }
  end

  def work
    entry, staff = scoped_case
    action = RecordFollowUp.new(
      outcome: params[:outcome], version: params[:version], issue_id: params[:issue], note: params[:note], appointment_ids: params[:appointment_ids]
    )
    result = action.call(follow_up: entry, staff_id: staff.id)
    render json: result, status: result[:error] ? :conflict : :ok
  end

  private

  def verification_patient(clinic, fields)
    return scoped_patient(clinic.id) unless params.key?(:originating_patient_id)

    require_access(fields[:originating_patient_id].to_s.match?(/\A[1-9]\d{0,18}\z/))

    origin = ContactProfilesQuery.scope(clinic.id, patient_ids: fields[:originating_patient_id]).find_by(id: fields[:originating_patient_id])
    permission = origin && ContactPermission.find_by(clinic_id: clinic.id, patient_id: origin.id)
    guardian = permission&.authorized_guarantor
    require_access(guardian && guardian.id != origin.id && guardian.id == origin.guarantor_id && guardian.id.to_s == params[:id])
    guardian
  end

  def calendar_date(today)
    return today if params[:date] == "today"
    Date.iso8601(params[:date].to_s)
  rescue ArgumentError
    raise ReminderFlow::Conflict, "Choose a valid appointment date."
  end

  def staff_scope(clinic_id: nil)
    staff = StaffMember.find_by(id: session[:staff])
    clinic_id = (clinic_id || params[:clinic].presence || staff&.clinic_id).to_i
    clinic = Clinic.messaging_enabled.find_by(id: clinic_id)
    require_access(staff && clinic && staff.clinic_id == clinic.id)
    [staff, clinic]
  end

  def scoped_case
    record = FollowUpCase.includes(:owner).find_by(id: params[:id].to_i)
    require_access(record)
    [record, *staff_scope(clinic_id: record.clinic_id)]
  end

  def scoped_patient(clinic_id)
    patient_id = params[:id]
    clinic_patients = ContactProfilesQuery.scope(clinic_id, patient_ids: patient_id)
    patient = clinic_patients.or(authorized_guardians(clinic_id, patient_id)).find_by(id: patient_id)
    require_access(patient)
    patient
  end

  def authorized_guardians(clinic_id, guardian_id)
    permissions = ContactPermission.where(clinic_id: clinic_id, authorized_guarantor_id: guardian_id)
      .joins(:patient).merge(Patient.where(guarantor_id: guardian_id))
    clinic_children = ContactProfilesQuery.scope(clinic_id, patient_ids: permissions.select(:patient_id))
    Patient.where(id: permissions.where(patient_id: clinic_children.select(:id)).select(:authorized_guarantor_id))
  end
end

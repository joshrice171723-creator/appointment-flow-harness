class CaseDetailQuery
  def self.call(entry, staff, clinic, patient: nil, now: Time.current)
    new(entry, staff, clinic, patient, now).call
  end

  def initialize(entry, staff, clinic, patient, now)
    @entry = entry
    @staff = staff
    @clinic = clinic
    @patient = patient
    if @patient.nil? && entry&.patient_id
      @patient = ContactProfilesQuery.call(clinic.id, patient_id: entry.patient_id).first
    end
    @now = now
  end

  def call
    result = {
      case: case_fields, staff: @staff.attributes, clinic: ClinicSerializer.as_json(@clinic),
      sync_status: SourceSync.status, issues: issues, person: nil, patient_name: nil,
      details: [], guardian: nil, guardian_review_required: false,
      next_appointment: nil, hold: nil, history: [], visits: []
    }
    return result unless @patient

    result.merge(patient_fields)
  end

  private

  def case_fields
    return unless @entry

    fields = @entry.attributes.merge("owner" => @entry.owner&.name)
    fields.delete("patient_id") unless @patient
    if @patient && @entry.state == "resolved"
      fields["resolution"] = FollowUpResolutionsQuery.call(@clinic.id, case_id: @entry.id)[@entry.id]
    end
    fields
  end

  def issues
    return [] unless @entry

    FollowUpIssue.where(case_id: @entry.id).includes(:resolution_event, :reply_event, visit: [:appointment, :clinic_setting])
      .order(:resolved, :resolved_at, :id).map do |issue|
      if @patient
        FollowUpIssueSerializer.new(issue, visible: true).as_json.merge(
          "resolution" => issue.resolution_event&.attributes&.slice("id", "actor", "kind", "body", "created_at")
        )
      else
        { "id" => issue.id, "code" => issue.code, "resolved_at" => issue.resolved_at,
          "reason" => "Restricted data issue" }
      end
    end
  end

  def patient_fields
    permission = @patient.contact_permission_for(@clinic.id)
    guardian = permission&.authorized_guarantor if @patient.guarantor_id.present? &&
      @patient.guarantor_id != @patient.id && @patient.guarantor_id == permission&.authorized_guarantor_id
    contact = ContactPolicy.new(@now).recipient(
      patient: @patient, permission: permission, timezone: @clinic.setting.timezone
    )
    appointments = PatientAppointmentsQuery.new(@patient, @clinic, now: @now)
    next_appointment = appointments.next_appointment
    outreach = appointments.next_outreach(next_appointment, permission)
    {
      person: { id: @patient.id, name: @patient.display_name, authorized_guardian_id: guardian&.id,
        contact: contact&.to_h&.slice(:phone, :email, :language, :name), allowed_channels: outreach.fetch(:allowed_channels),
        phone_on_file: (contact ? contact.phone_on_file : @patient.wireless_phone).presence },
      patient_name: @patient.display_name, details: detail_fields(@patient),
      guardian: guardian && { id: guardian.id, name: guardian.display_name, details: detail_fields(guardian) },
      guardian_review_required: @patient.guarantor_id.present? && guardian.nil?,
      next_appointment: next_appointment && appointments.rows([next_appointment.id])[next_appointment.id],
      hold: outreach.fetch(:hold),
      history: @entry ? ActivityHistoryQuery.call(@entry, @clinic) : [],
      visits: recent_visits(appointments)
    }
  end

  def recent_visits(appointments)
    ids = Visit.current.for_clinic(@clinic.id).for_patient(@patient.id)
      .chronological.limit(PatientWorkspaceHistory::PAGE_SIZE).pluck(:appointment_id)
    appointments.rows(ids).values
  end

  def detail_fields(patient)
    active = patient.active_detail_verifications.includes(:staff).index_by(&:field)
    PatientDetailVerification::FIELDS.map do |field, label|
      verification = active[field]
      local_staff = verification&.staff if verification&.staff&.clinic_id == @clinic.id
      {
        field: field, label: label, pms_value: patient.read_attribute(field),
        verified_value: verification&.verified_value,
        verified_at: (verification.verified_at if local_staff), verified_by: local_staff&.name,
        conflict: verification&.conflicted_at.present?,
        matches_pms: verification&.aligned_at.present? && !verification.conflicted_at,
        token: PatientDetailVerification.review_token(patient, field, verification)
      }
    end
  end
end

class FollowUpIssueSerializer
  def initialize(issue, visible:)
    @issue = issue
    @visible = visible
  end

  def as_json
    visit = @issue.visit
    result = @issue.attributes.merge(
      visit.attributes.slice("appointment_id", "start_at", "current")
    )
    return result.merge("reason" => "Restricted data issue") unless @visible

    if @issue.reply_event_id
      candidates = Visit.for_clinic(visit.clinic_id).where(patient_id: visit.patient_id, id: @issue.candidate_visit_ids)
      return result.except("appointment_id", "start_at").merge(
        "reply" => @issue.reply_event.attributes.slice("id", "body", "created_at"),
        "candidate_appointments" => candidates.map { |candidate| candidate.attributes.slice("id", "appointment_id", "start_at", "current") }
      )
    end

    source = visit.appointment if visit.matches_appointment?(visit.appointment)
    result.merge(
      "start_at_utc" => visit.starts_at_utc&.iso8601,
      "pms_status" => source&.status,
      "provider_name" => source&.provider_name,
      "outcome" => source&.outcome || "unknown"
    )
  end
end

class BoardCaseSerializer
  def initialize(entry, resolution:, latest:)
    @entry = entry
    @resolution = resolution
    @latest = latest
  end

  def as_json
    open_issues = @entry.issues.select { |issue| issue.resolved_at.nil? }.sort_by(&:id)
    unanswered_starts = open_issues.select { |issue| issue.code == "no_response" }.filter_map { |issue| issue.visit.starts_at_utc }
    issue_codes = open_issues.map(&:code)
    has_open_issues = open_issues.any?
    patient_available = @entry.patient.present?
    reason = if patient_available
      open_issues.map(&:reason).join(" · ") if has_open_issues
    else
      "Restricted data issue"
    end

    @entry.attributes.slice("id", "patient_id", "state", "due_at").merge(
      "owner" => @entry.owner&.name,
      "name" => patient_available ? @entry.patient.display_name : "Patient mapping needs review",
      "reason" => reason,
      "latest" => patient_available ? @latest : nil,
      "visits" => patient_available ? open_issues.flat_map(&:affected_visit_ids).uniq.length : nil,
      "first_visit" => patient_available ? open_issues.map { |issue| issue.visit.start_at }.min : nil,
      "reminders_blocked" => issue_codes.include?("contact"),
      "reply_review" => issue_codes.intersect?(%w[patient ambiguous_reply]),
      "no_response_start_at" => patient_available ? unanswered_starts.min&.iso8601 : nil,
      "no_response" => issue_codes.include?("no_response"),
      "delivery_failed" => issue_codes.include?("delivery"),
      "resolution" => @resolution
    )
  end
end

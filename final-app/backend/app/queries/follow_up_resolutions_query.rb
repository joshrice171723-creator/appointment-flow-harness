class FollowUpResolutionsQuery
  def self.call(clinic_id, case_id: nil)
    cases = FollowUpCase.for_clinic(clinic_id).where(state: "resolved")
    cases = cases.where(id: case_id) if case_id

    cases.includes(issues: :resolution_event).to_h do |follow_up|
      latest_issue = follow_up.issues.max_by do |issue|
        [issue.resolved_at || Time.at(0), issue.resolution_event_id || 0, issue.id]
      end
      event = latest_issue&.resolution_event
      summary = {
        "case_id" => follow_up.id,
        "at" => latest_issue&.resolved_at,
        "actor" => event&.actor,
        "kind" => event&.kind,
        "reason" => event&.body
      }
      [follow_up.id, summary]
    end
  end
end

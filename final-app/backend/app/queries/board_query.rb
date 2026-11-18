class BoardQuery
  def self.call(clinic_id)
    resolutions = FollowUpResolutionsQuery.call(clinic_id)
    cases = FollowUpCase.for_clinic(clinic_id)
    latest_ids = ActivityEvent.where(case_id: cases.select(:id)).group(:case_id).maximum(:id)
    latest_events = ActivityEvent.where(id: latest_ids.values).pluck(:case_id, :body).to_h
    cases.includes(:patient, :owner, issues: { visit: :clinic_setting }).map do |entry|
      BoardCaseSerializer.new(entry, resolution: resolutions[entry.id], latest: latest_events[entry.id]).as_json
    end.sort_by do |entry|
      [entry["state"] == "attention" && entry["reply_review"] ? 0 : 1, entry["due_at"], entry["id"]]
    end
  end
end

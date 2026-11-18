class FollowUpIssue < ApplicationRecord
  self.table_name = "desk.issues"
  belongs_to :follow_up_case, foreign_key: :case_id
  belongs_to :resolution_event, class_name: "ActivityEvent", optional: true
  belongs_to :reply_event, class_name: "ActivityEvent", optional: true
  belongs_to :visit
  has_many :candidates, class_name: "IssueCandidate", foreign_key: :issue_id, dependent: :delete_all
  after_save :sync_candidates, if: -> {
    saved_change_to_id? || saved_change_to_visit_id? || saved_change_to_candidate_visit_ids?
  }
  scope :open, -> { where(resolved_at: nil) }
  scope :for_clinic, ->(id) { where(case_id: FollowUpCase.for_clinic(id).select(:id)) }
  def self.for_visits(ids)
    where(id: IssueCandidate.where(visit_id: ids).select(:issue_id))
  end

  # Index the owning visit as well as possible reply targets. JSON stays the recorded input.
  def indexed_visit_ids
    [visit_id, *candidate_visit_ids].uniq
  end

  def self.index_visits(issues)
    rows = issues.flat_map do |issue|
      issue.indexed_visit_ids.map { |id| { issue_id: issue.id, visit_id: id } }
    end
    IssueCandidate.insert_all(rows, returning: false) if rows.any?
  end

  def sync_candidates
    candidates.where.not(visit_id: indexed_visit_ids).delete_all unless previously_new_record?
    self.class.index_visits([self])
  end

  def affected_visit_ids
    return [visit_id] unless reply_event_id
    resolved_at ? clarified_visit_ids : candidate_visit_ids
  end

  def self.group_by_visit(issues)
    result = Hash.new { |hash, id| hash[id] = [] }
    issues.each { |issue| issue.affected_visit_ids.each { |id| result[id] << issue } }
    result
  end
end

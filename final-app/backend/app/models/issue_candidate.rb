class IssueCandidate < ApplicationRecord
  self.table_name = "desk.issue_candidates"
  self.primary_key = [:issue_id, :visit_id]
  belongs_to :issue, class_name: "FollowUpIssue"
  belongs_to :visit
end

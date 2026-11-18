class FollowUpCase < ApplicationRecord
  self.table_name = "desk.cases"
  belongs_to :patient, optional: true
  belongs_to :owner, class_name: "StaffMember", optional: true
  has_many :issues, class_name: "FollowUpIssue", foreign_key: :case_id
  has_many :events, class_name: "ActivityEvent", foreign_key: :case_id
  scope :for_clinic, ->(id) { where(clinic_id: id) }

  def changed_for_staff?(staff, version:)
    self.version != version || state == "resolved" || (owner_id && owner_id != staff.id)
  end

  def mark_in_progress!(staff:, at:)
    update!(owner_id: staff.id, state: "progress", version: version + 1, updated_at: at)
  end
end

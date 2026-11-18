class ActivityEvent < ApplicationRecord
  self.table_name = "desk.events"
  belongs_to :visit, optional: true
  belongs_to :message, optional: true

  scope :pms_change, -> { where(kind: %w[rescheduled canceled]) }

  def self.record(actor:, kind:, body:, at:, case_id: nil, visit_id: nil, message_id: nil, request_key: nil,
                  issue_id: nil, previous_resolution_event_id: nil)
    create!(
      actor: actor, kind: kind, body: body, created_at: at,
      case_id: case_id, visit_id: visit_id, message_id: message_id, request_key: request_key,
      issue_id: issue_id, previous_resolution_event_id: previous_resolution_event_id
    ).id
  end
end

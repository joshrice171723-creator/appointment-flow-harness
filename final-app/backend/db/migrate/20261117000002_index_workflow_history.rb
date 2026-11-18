class IndexWorkflowHistory < ActiveRecord::Migration[8.1]
  def up
    add_index "desk.message_items", :message_id
    add_index "desk.messages", [:clinic_id, :channel, :sender, :destination],
      where: "status = 'sent'", name: :sent_conversation
    add_index "desk.events", :visit_id
    add_index "desk.issues", :visit_id, where: "resolved_at IS NULL", name: :open_issue_visits
    FollowUpIssue.find_in_batches { |issues| FollowUpIssue.index_visits(issues) }
  end

  def down
    remove_index "desk.issues", name: :open_issue_visits
    remove_index "desk.events", :visit_id
    remove_index "desk.messages", name: :sent_conversation
    remove_index "desk.message_items", :message_id
    # Keeping owning-visit links is compatible with the previous membership query.
  end
end

class LinkReplyReviews < ActiveRecord::Migration[8.1]
  def change
    add_reference "desk.issues", :reply_event, foreign_key: { to_table: "desk.events" }, index: { unique: true }
    add_column "desk.issues", :candidate_visit_ids, :jsonb, null: false, default: []
    add_column "desk.issues", :clarified_visit_ids, :jsonb, null: false, default: []
    remove_index "desk.issues", name: "index_issues_on_visit_id_and_code"
    add_index "desk.issues", [:visit_id, :code], unique: true, where: "reply_event_id IS NULL", name: "visit_issue_without_reply"
  end
end

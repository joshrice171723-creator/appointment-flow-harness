class ConvertOpenReplyReviews < ActiveRecord::Migration[8.1]
  class Issue < ActiveRecord::Base
    self.table_name = "desk.issues"
  end
  class Event < ActiveRecord::Base
    self.table_name = "desk.events"
  end

  def up
    Issue.reset_column_information
    Issue.where(code: %w[patient ambiguous_reply], resolved_at: nil, reply_event_id: nil).group(:case_id).pluck(:case_id).each do |case_id|
      issues = Issue.where(case_id: case_id, code: %w[patient ambiguous_reply], resolved_at: nil, reply_event_id: nil).order(:id).to_a
      owner = select_one("SELECT patient_id, clinic_id FROM desk.cases WHERE id = #{connection.quote(case_id)}")
      replies = Event.joins("JOIN desk.messages ON desk.messages.id = desk.events.message_id")
        .where(actor: "Patient", kind: %w[reply ambiguous_reply])
        .where("desk.messages.patient_id = ? AND desk.messages.clinic_id = ?", owner.fetch("patient_id"), owner.fetch("clinic_id"))
        .where("desk.events.created_at >= ?", issues.map(&:created_at).min).order(:created_at, :id)
      next if replies.empty?

      # Legacy tasks recorded candidate visits, but did not link each task to its reply.
      # Retain those recorded candidates rather than infer a match from message text.
      candidates = issues.map(&:visit_id).uniq
      reviews = replies.map.with_index do |reply, index|
        issue = issues[index] || Issue.new(case_id: case_id, visit_id: candidates.first)
        issue.assign_attributes(code: reply.kind == "ambiguous_reply" ? "ambiguous_reply" : "patient",
          reason: "Clarify this patient reply.", reply_event_id: reply.id, candidate_visit_ids: candidates,
          created_at: reply.created_at)
        issue.save!
        reply.update!(case_id: case_id)
        issue
      end
      extras = issues.drop(reviews.length)
      Event.where(issue_id: extras.map(&:id)).update_all(issue_id: reviews.first.id)
      Issue.where(id: extras.map(&:id)).delete_all
      execute "UPDATE desk.cases SET version = version + 1 WHERE id = #{connection.quote(case_id)}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reply reviews preserve incoming reply identities."
  end
end

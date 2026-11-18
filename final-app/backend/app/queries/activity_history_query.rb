class ActivityHistoryQuery
  def self.call(entry, clinic)
    patient_visits = Visit.for_clinic(clinic.id).for_patient(entry.patient_id).select(:id)
    case_events = ActivityEvent.where(case_id: entry.id)
    patient_events = ActivityEvent.where(visit_id: patient_visits)
    delivery_events = ActivityEvent.where.not(message_id: nil).where(kind: %w[sent failed])
    events = case_events.or(patient_events).where.not(id: delivery_events.select(:id))

    event_history = events.order(created_at: :desc, id: :desc).limit(60).map do |event|
      event.attributes.slice("id", "actor", "kind", "body", "created_at").merge(
        "entry_type" => "event",
        "purposes" => nil
      )
    end

    messages = Message.conversation(clinic.id, entry.patient_id)
      .includes(:items).order(created_at: :desc, id: :desc).limit(30)
    message_history = messages.map do |message|
      message.attributes.slice("id", "body", "created_at").merge(
        "entry_type" => "receipt",
        "actor" => message.channel,
        "kind" => message.status,
        "purposes" => message.items.map(&:purpose).uniq.sort.join(", ").presence
      )
    end

    (event_history + message_history).sort_by do |item|
      [-item["created_at"].to_f, item["entry_type"], -item["id"]]
    end
  end
end

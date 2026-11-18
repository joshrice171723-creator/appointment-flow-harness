class PatientInboxSerializer
  def initialize(messages)
    @messages = messages
  end

  def as_json
    replies = @messages.flat_map do |message|
      message.events.select { |event| event.actor == "Patient" }.map do |event|
        event.attributes.slice("id", "created_at", "body").merge("token" => message.token)
      end
    end

    messages = @messages.map do |message|
      recipient_id = message.recipient_id || message.patient_id
      message.attributes.slice(
        "token", "channel", "clinic_id", "patient_id", "sender",
        "destination", "created_at", "body"
      ).merge("sent_to_guarantor" => recipient_id != message.patient_id)
    end

    {
      messages: messages,
      replies: replies.sort_by { |reply| [reply["created_at"], reply["id"]] }
    }
  end
end

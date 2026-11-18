class ReceiveReply
  MAX_REPLY_LENGTH = 1000
  MAX_REQUEST_KEY_LENGTH = 100
  SMS_REPLY_LOOKBACK = 48.hours
  REPLY_RESULTS = {
    "opt_out" => "Texts stopped for this number.",
    "late_reply" => "Reply saved to message history.",
    "ambiguous_reply" => "Reply sent to Needs attention.",
    "reply" => "Reply sent to Needs attention.",
    "confirmation" => "Appointment confirmed."
  }.freeze

  def initialize(now:)
    @now = now
    @contacts = ContactPolicy.new(now)
    @follow_ups = FollowUpWorkflow.new(now: now)
  end

  def reply_to_receipt(receipt:, text:, request_key:)
    ApplicationRecord.uncached do
      ApplicationRecord.transaction do
        Database.lock_clinic(receipt.clinic_id)
        current_receipt = Message.sent.find_by(id: receipt.id, clinic_id: receipt.clinic_id, token: receipt.token)
        raise ReminderFlow::Conflict, "Open the appropriate workspace first." unless current_receipt

        record_once(text: text, receipt: current_receipt, request_key: request_key) do
          visit_id = current_receipt.items.order(:visit_id).pick(:visit_id)
          visit = Visit.for_clinic(receipt.clinic_id).with_messaging_context.find_by(id: visit_id) if visit_id
          raise ReminderFlow::Conflict, "Open the appropriate workspace first." unless visit&.patient

          process(visit, text: text, receipt: current_receipt, request_key: request_key)
        end
      end
    end
  end

  # Assessment replay already has the visit matched to its synthetic receipt.
  def reply(visit:, text:, receipt:, request_key:)
    ApplicationRecord.transaction do
      Database.lock_clinic(visit.clinic_id)
      record_once(text: text, receipt: receipt, request_key: request_key) do
        process(visit, text: text, receipt: receipt, request_key: request_key)
      end
    end
  end

  private

  def record_once(text:, receipt:, request_key:)
    validate_input!(text, request_key)
    Database.lock_request(request_key)
    if (recorded = ActivityEvent.find_by(request_key: request_key))
      unless recorded.message_id == receipt.id && recorded.body == text && REPLY_RESULTS.key?(recorded.kind)
        raise ReminderFlow::Conflict, "This reply key was already used for a different reply."
      end

      return REPLY_RESULTS.fetch(recorded.kind)
    end

    yield
  end

  def validate_input!(text, request_key)
    unless text.present? && text.length <= MAX_REPLY_LENGTH && request_key.present? && request_key.length <= MAX_REQUEST_KEY_LENGTH
      raise ReminderFlow::Conflict, "Enter a reply of up to 1,000 characters."
    end
  end

  def process(visit, text:, receipt:, request_key:)
    if receipt.channel == "SMS" && text.casecmp?("STOP") && receipt.destination
      return stop_texts(visit, text, receipt: receipt, request_key: request_key)
    end

    candidate_ids = reply_candidate_ids(visit, receipt)
    candidates = current_candidates(visit.clinic_id, candidate_ids).select { |candidate| candidate.patient_id == visit.patient_id }
    if candidates.empty?
      return save_late_reply(visit, text, candidate_ids: candidate_ids, receipt: receipt, request_key: request_key)
    end

    contact = @contacts.for_visit(visit)
    one_matching_visit = candidate_ids == [visit.id] && candidates.first.id == visit.id
    unless one_matching_visit && contact && matches_reply_recipient?(visit, contact, receipt)
      return request_matching_review(candidates, text, receipt: receipt, request_key: request_key)
    end

    if can_auto_confirm?(visit, text, contact) && confirm_reply(visit, text, receipt: receipt, request_key: request_key)
      return REPLY_RESULTS.fetch("confirmation")
    end

    request_patient_review(visit, text, receipt: receipt, request_key: request_key)
  end

  def stop_texts(visit, text, receipt:, request_key:)
    OptOut.insert_all([{ clinic_id: visit.clinic_id, destination: receipt.destination }])
    record_reply("opt_out", text, visit_id: visit.id, receipt: receipt, request_key: request_key)
    REPLY_RESULTS.fetch("opt_out")
  end

  def current_candidates(clinic_id, candidate_ids)
    Visit.current.for_clinic(clinic_id).where(id: candidate_ids).with_context
      .select { |candidate| candidate.current_reply_target?(now: @now, source: candidate.appointment) }
  end

  def save_late_reply(visit, text, candidate_ids:, receipt:, request_key:)
    attributed_visit = visit.id if receipt.channel == "Email" && candidate_ids == [visit.id]
    record_reply("late_reply", text, visit_id: attributed_visit, receipt: receipt, request_key: request_key)
    REPLY_RESULTS.fetch("late_reply")
  end

  def request_matching_review(candidates, text, receipt:, request_key:)
    reply_id = record_reply("ambiguous_reply", text, receipt: receipt, request_key: request_key)
    case_id = @follow_ups.issue(candidates.first, "ambiguous_reply", "Clarify which appointments this reply concerns.",
      reply_event_id: reply_id, candidate_visit_ids: candidates.map(&:id))
    ActivityEvent.find(reply_id).update!(case_id: case_id)
    REPLY_RESULTS.fetch("ambiguous_reply")
  end

  def can_auto_confirm?(visit, text, contact)
    ReplyClassification.call(text) == :affirmative && !@contacts.hold(visit, contact: contact) && !SourceSync.status["stale"]
  end

  def confirm_reply(visit, text, receipt:, request_key:)
    visit.confirm!(actor: "Patient", at: @now)
    @follow_ups.close_after_confirmation(visit, actor: "Patient", event_kind: "confirmation")
    record_reply("confirmation", text, visit_id: visit.id, receipt: receipt, request_key: request_key)
    true
  rescue ReminderFlow::Conflict
    # A pending PMS change requires staff review, even for a clear YES.
    false
  end

  def request_patient_review(visit, text, receipt:, request_key:)
    reply_id = record_reply("reply", text, visit_id: visit.id, receipt: receipt, request_key: request_key)
    case_id = @follow_ups.issue(visit, "patient", "Clarify this patient reply.",
      reply_event_id: reply_id, candidate_visit_ids: [visit.id])
    ActivityEvent.find(reply_id).update!(case_id: case_id)
    REPLY_RESULTS.fetch("reply")
  end

  def record_reply(kind, text, receipt:, request_key:, case_id: nil, visit_id: nil)
    ActivityEvent.record(
      actor: "Patient", kind: kind, body: text, at: @now,
      case_id: case_id, visit_id: visit_id, message_id: receipt.id, request_key: request_key
    )
  end

  def matches_reply_recipient?(visit, contact, receipt)
    destination = if receipt.channel == "SMS"
      @contacts.phone(receipt.destination)
    else
      @contacts.address(receipt.destination)
    end
    expected = receipt.channel == "SMS" ? contact.phone : contact.email
    recipient_id = receipt.recipient_id || receipt.patient_id
    return false unless destination && expected == destination && contact.id == recipient_id

    peers = ContactProfilesQuery.sharing_destination(visit.clinic_id,
      channel: receipt.channel, destination: destination, except: visit.patient_id)
    peers.none? do |patient|
      peer_contact = @contacts.recipient(
        patient: patient, permission: patient.contact_permission_for(visit.clinic_id), timezone: visit.timezone
      )
      peer_destination = receipt.channel == "SMS" ? peer_contact&.phone : peer_contact&.email
      peer_destination&.casecmp?(destination)
    end
  end

  def reply_candidate_ids(visit, receipt)
    return receipt.items.distinct.pluck(:visit_id) unless receipt.channel == "SMS"

    # A delayed YES can refer to a recently ended or superseded visit.
    zone = Time.find_zone(visit.timezone)
    local_now = zone ? @now.in_time_zone(zone) : @now.utc
    cutoff = (local_now - SMS_REPLY_LOOKBACK).strftime("%F %T")
    messages = Message.sent.where(
      clinic_id: visit.clinic_id, channel: "SMS", sender: receipt.sender, destination: receipt.destination
    )
    candidates = Visit.where(id: MessageItem.where(message_id: messages.select(:id)).select(:visit_id))
    candidates.where(start_at: cutoff..).or(candidates.where(id: visit.id)).pluck(:id)
  end
end

require "securerandom"

# Runs inside ReminderFlow's batch transaction. ContactPolicy selects recipients;
# ReminderSchedule selects due purposes; this class records delivery and contact work.
class ReminderSender
  NO_RESPONSE_LEAD_TIME = 48.hours
  RECEIPT_TOKEN_BYTES = 16

  def initialize(transport:, now:, contact_policy:, message_templates:, follow_ups:)
    @transport = transport
    @now = now
    @contact_policy = contact_policy
    @message_templates = message_templates
    @follow_ups = follow_ups
  end

  def call(visits:, clinic_id:, send_reminders:)
    @pending_deliveries = []
    visit_ids = visits.map(&:id)
    pending_change_ids = Visit.current.where(id: visit_ids).with_pending_pms_change.pluck(:id).to_set
    issues = FollowUpIssue.for_visits(visit_ids).to_a
    issues_by_owner = issues.group_by(&:visit_id)
    # A handled reply still suppresses another confirmation request.
    responded_visit_ids = issues.select { |issue| %w[patient ambiguous_reply].include?(issue.code) }.flat_map(&:affected_visit_ids).to_set
    responded_visit_ids.merge(ActivityEvent.where(visit_id: visit_ids, kind: "opt_out").pluck(:visit_id))
    open_issues_by_visit = FollowUpIssue.group_by_visit(issues.select { |issue| issue.resolved_at.nil? })
    opt_outs = OptOut.where(clinic_id: clinic_id).pluck(:destination).to_set
    attempts_by_visit = if send_reminders
      MessageItem.where(visit_id: visit_ids).includes(:message).group_by(&:visit_id)
    else
      {}
    end

    @follow_ups.with_locked_reminder_cases(clinic_id, visits.map(&:patient_id).uniq) do
      count = visits.sum do |visit|
        process_visit(
          visit, pending_change: pending_change_ids.include?(visit.id),
          responded: responded_visit_ids.include?(visit.id), open_issues: open_issues_by_visit.fetch(visit.id, []),
          visit_issues: issues_by_owner.fetch(visit.id, []), opt_outs: opt_outs,
          attempts: attempts_by_visit.fetch(visit.id, []), send_reminders: send_reminders
        )
      end
      flush_deliveries
      count
    end
  ensure
    @pending_deliveries = nil
  end

  def deliver(visit:, channel:, destination:, purposes:, recipient_id:)
    contact = @contact_policy.for_visit(visit)
    body = @message_templates.message_body(visit, channel, purposes, language: contact&.language)
    token = SecureRandom.hex(RECEIPT_TOKEN_BYTES)
    status, receipt = @transport.deliver(channel: channel, destination: destination, body: body, key: token)
    attributes = {
      patient_id: visit.patient_id, clinic_id: visit.clinic_id,
      clinic_name: visit.clinic.name, sender: visit.sender,
      channel: channel, destination: destination, body: body, token: token,
      created_at: @now, status: status, receipt: receipt, recipient_id: recipient_id
    }
    delivery = { attributes: attributes, visit_id: visit.id, purposes: purposes }
    if @pending_deliveries
      @pending_deliveries << delivery
    else
      persist_deliveries([delivery])
    end
    if status == "failed"
      flush_deliveries
      @follow_ups.issue(visit, "delivery", "#{channel} delivery failed. Review contact details.")
    end
    status
  end

  private

  def flush_deliveries
    return unless @pending_deliveries&.any?
    persist_deliveries(@pending_deliveries)
    @pending_deliveries.clear
  end

  def persist_deliveries(deliveries)
    rows = deliveries.map { |delivery| delivery.fetch(:attributes) }
    # These records have no save callbacks. Preserve validation and database constraints.
    rows.each { |attributes| Message.new(attributes).validate! }
    ids = Message.insert_all!(rows, returning: %w[id token]).to_h { |row| [row.fetch("token"), row.fetch("id")] }
    items = []
    events = deliveries.map do |delivery|
      attributes = delivery.fetch(:attributes)
      id = ids.fetch(attributes.fetch(:token))
      visit_id = delivery.fetch(:visit_id)
      purposes = delivery.fetch(:purposes)
      purposes.each { |purpose| items << { message_id: id, visit_id: visit_id, purpose: purpose } }
      { actor: "Fake #{attributes.fetch(:channel)}", kind: attributes.fetch(:status),
        body: purposes.join(", "), created_at: @now, visit_id: visit_id, message_id: id }
    end
    MessageItem.insert_all!(items, returning: false)
    ActivityEvent.insert_all!(events, returning: false)
  end

  def process_visit(visit, pending_change:, responded:, open_issues:, visit_issues:, opt_outs:, attempts:, send_reminders:)
    return 0 if pending_change || !within_outreach_window?(visit)

    decision = @contact_policy.decision(visit, opt_outs: opt_outs)
    # Persist earlier receipts before contact work can add activity at the same time.
    if open_issues.any? || decision.reason_code || visit.starts_at_utc <= @now + NO_RESPONSE_LEAD_TIME
      flush_deliveries
    end
    reconcile_contact_work(visit, decision: decision, responded: responded, open_issues: open_issues, visit_issues: visit_issues)
    review_pending = open_issues.any? { |issue| %w[patient ambiguous_reply].include?(issue.code) }
    return 0 if decision.reason_code || !send_reminders || review_pending

    send_due_reminders(visit, contact: decision.recipient, destinations: decision.destinations,
      attempts: attempts, responded: responded)
  end

  def within_outreach_window?(visit)
    start = visit.starts_at_utc
    return true unless start # Invalid wall times need a visible hold.
    return false if start <= @now

    initial_at = visit.reminder_at(days_before: ReminderSchedule::INITIAL_DAYS_BEFORE)
    initial_at.nil? || @now >= initial_at
  end

  def reconcile_contact_work(visit, decision:, responded:, open_issues:, visit_issues:)
    needs_response = !decision.reason_code && !visit.confirmed_at && !responded && visit.starts_at_utc <= @now + NO_RESPONSE_LEAD_TIME
    codes = open_issues.map(&:code)
    if codes.include?("no_response") && !needs_response
      @follow_ups.close_visit_follow_ups(visit, "The visit no longer needs a no-response follow-up.", codes: ["no_response"])
    end
    if decision.reason_code
      if decision.reason_code == :conflicting_details || !visit.confirmed_at
        @follow_ups.issue(visit, "contact", decision.reason, reason_code: decision.reason_code, visit_issues: visit_issues)
      elsif open_issues.any? { |issue| issue.reason_code == "conflicting_details" } &&
            !@contact_policy.verification_conflict?(visit)
        @follow_ups.close_visit_follow_ups(visit, "The verified details conflict cleared.", codes: ["contact"])
      end
      return
    end
    if codes.include?("contact")
      @follow_ups.close_visit_follow_ups(visit, ContactPolicy::CHANNEL_RESTORED, codes: ["contact"])
    end
    if needs_response
      @follow_ups.issue(visit, "no_response", "No reply and the appointment is within 48 hours. Contact the patient.", visit_issues: visit_issues)
    end
  end

  def send_due_reminders(visit, contact:, destinations:, attempts:, responded:)
    attempts_by_purpose = attempts.to_h { |item| [item.purpose, item.message] }
    purposes = ReminderSchedule.new(
      visit: visit, now: @now, attempts_by_purpose: attempts_by_purpose, responded: responded,
      email_available: destinations.key?(ContactPolicy::EMAIL_CHANNEL)
    ).purposes
    return 0 if purposes.empty?

    channel = purposes.include?("backup") ? ContactPolicy::EMAIL_CHANNEL : destinations.keys.first
    status = deliver(
      visit: visit, channel: channel, destination: destinations.fetch(channel),
      purposes: purposes, recipient_id: contact.id
    )
    initial_sms_failed = status == "failed" && channel == ContactPolicy::SMS_CHANNEL && purposes.include?("initial")
    email_fallback_available = destinations.key?(ContactPolicy::EMAIL_CHANNEL)
    return 1 unless initial_sms_failed && email_fallback_available

    deliver(visit: visit, channel: ContactPolicy::EMAIL_CHANNEL, destination: destinations.fetch(ContactPolicy::EMAIL_CHANNEL),
            purposes: ["backup"], recipient_id: contact.id)
    2
  end
end

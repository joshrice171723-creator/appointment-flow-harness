require "base64"

class PatientWorkspaceHistory
  PAGE_SIZE = 25
  FILTERS = {
    "appointments" => %w[all upcoming past],
    "follow_up" => %w[all open resolved],
    "activity" => %w[all messages replies staff verifications]
  }.freeze

  def initialize(patient, clinic)
    @patient = patient
    @clinic = clinic
    @visits = Visit.for_clinic(clinic.id).for_patient(patient.id)
    @cases = FollowUpCase.for_clinic(clinic.id).where(patient_id: patient.id)
  end

  def call(section: nil, filter: "all", cursor: nil, appointment_id: nil, message_id: nil)
    unless FILTERS.fetch(section, []).include?(filter) &&
           (!appointment_id || valid_id?(appointment_id)) &&
           (!message_id || (section == "activity" && valid_id?(message_id)))
      raise ReminderFlow::Conflict, "Choose a valid history section or filter."
    end

    @appointment_id = appointment_id
    @message_id = message_id
    @before = decode(cursor, section, filter)
    entries = case section
    when "appointments" then appointments(filter)
    when "follow_up" then follow_up(filter)
    when "activity" then activity(filter)
    end
    page = entries.first(PAGE_SIZE)
    next_cursor = if entries.length > PAGE_SIZE
      _, time, type, id = page.last
      Base64.urlsafe_encode64(JSON.generate([section, filter, appointment_id, message_id, @clinic.id, @patient.id, time.iso8601(6), type, id]), padding: false)
    end
    { rows: page.map(&:first), next_cursor: next_cursor }
  end

  private

  def valid_id?(id)
    id.to_s.match?(/\A[1-9]\d{0,18}\z/)
  end

  def decode(cursor, section, filter)
    return unless cursor
    raise ArgumentError unless cursor.is_a?(String) && cursor.bytesize <= 350

    saved_section, saved_filter, saved_appointment, saved_message, clinic_id, patient_id, timestamp, type, id = JSON.parse(Base64.urlsafe_decode64(cursor))
    unless [saved_section, saved_filter, saved_appointment, saved_message, clinic_id, patient_id] ==
           [section, filter, @appointment_id, @message_id, @clinic.id, @patient.id] &&
           %w[appointment issue receipt event verification].include?(type) && id.is_a?(Integer) && id.positive?
      raise ArgumentError
    end

    [Time.iso8601(timestamp), type, id]
  rescue ArgumentError, TypeError, JSON::ParserError
    raise ReminderFlow::Conflict, "Reload history before continuing."
  end

  def appointments(filter)
    query = PatientAppointmentsQuery.new(@patient, @clinic)
    ids = query.page(filter: filter, before: @before && @before.values_at(0, 2), limit: PAGE_SIZE + 1, appointment_id: @appointment_id)
    rows = query.rows(ids.map(&:first))
    ids.filter_map do |id, time|
      next unless rows.key?(id)

      [rows.fetch(id), time.respond_to?(:iso8601) ? time : Time.parse(time), "appointment", id]
    end
  end

  def follow_up(filter)
    issues = FollowUpIssue.where(case_id: @cases.select(:id)).for_visits(scoped_visits.select(:id))
      .includes(:resolution_event, :reply_event, visit: [:appointment, :clinic_setting])
    issues = issues.open if filter == "open"
    issues = issues.where.not(resolved_at: nil) if filter == "resolved"
    paginate(issues, "issue").map do |issue|
      row = FollowUpIssueSerializer.new(issue, visible: true).as_json
      row["resolution"] = issue.resolution_event&.attributes&.slice("id", "actor", "kind", "body", "created_at")
      [row, issue.created_at, "issue", issue.id]
    end
  end

  def activity(filter)
    messages = Message.conversation(@clinic.id, @patient.id)
    messages = messages.where(id: MessageItem.where(visit_id: scoped_visits.select(:id)).select(:message_id)) if @appointment_id
    messages = messages.where(id: @message_id) if @message_id
    entries = []
    if %w[all messages].include?(filter)
      entries.concat(paginate(messages.includes(items: :visit), "receipt").map do |message|
        row = message.attributes.slice("id", "body", "created_at", "channel", "destination", "recipient_id")
        row.merge!("entry_type" => "receipt", "actor" => message.channel, "kind" => message.status,
          "message_id" => message.id, "purposes" => message.items.map(&:purpose).uniq.sort.join(", ").presence,
          "appointment_ids" => message.items.filter_map { |item| visible_appointment_id(item.visit) }.uniq)
        [row, message.created_at, "receipt", message.id]
      end)
    end

    if %w[all replies staff].include?(filter)
      event_scope = ActivityEvent.where(visit_id: scoped_visits.select(:id))
        .or(ActivityEvent.where(message_id: messages.select(:id)))
      event_scope = event_scope.or(ActivityEvent.where(case_id: @cases.select(:id))) unless @appointment_id
      event_scope = event_scope.where(message_id: messages.select(:id)) if @message_id
      duplicates = ActivityEvent.where(message_id: messages.select(:id), kind: %w[sent failed])
      event_scope = event_scope.where.not(id: duplicates.select(:id))
      replies = ActivityEvent.where(actor: "Patient").or(ActivityEvent.where(kind: "ambiguous_reply"))
      event_scope = event_scope.where(id: replies.select(:id)) if filter == "replies"
      event_scope = event_scope.where.not(id: replies.select(:id)) if filter == "staff"
      visible_cases = @cases.ids.to_set
      entries.concat(paginate(event_scope.includes(:visit, :message), "event").map do |event|
        row = event.attributes.slice("id", "actor", "kind", "body", "created_at", "case_id",
          "visit_id", "message_id", "issue_id", "previous_resolution_event_id")
        unless visible_cases.include?(event.case_id)
          row.except!("case_id", "issue_id", "previous_resolution_event_id")
        end
        message = event.message
        if message && message.clinic_id == @clinic.id && message.patient_id == @patient.id
          row.merge!(message.attributes.slice("channel", "destination", "recipient_id"))
        else
          row.delete("message_id")
        end
        appointment_id = visible_appointment_id(event.visit)
        row.delete("visit_id") unless appointment_id
        row.merge!("entry_type" => "event", "appointment_ids" => [appointment_id].compact)
        [row, event.created_at, "event", event.id]
      end)
    end

    if %w[all verifications].include?(filter) && !@appointment_id && !@message_id
      staff = StaffMember.where(clinic_id: @clinic.id)
      subjects = [@patient.id]
      permission = @patient.contact_permission_for(@clinic.id)
      guardian_id = permission&.authorized_guarantor_id
      subjects << guardian_id if guardian_id && guardian_id != @patient.id && guardian_id == @patient.guarantor_id
      verifications = PatientDetailVerification.where(patient_id: subjects, staff_id: staff.select(:id)).includes(:staff)
      entries.concat(paginate(verifications, "verification", time_column: :verified_at).map do |detail|
        row = detail.attributes.slice("id", "patient_id", "field", "pms_value", "verified_value", "retired_at")
        row.merge!("entry_type" => "verification", "actor" => detail.staff.name, "kind" => "verified",
          "body" => PatientDetailVerification::FIELDS.fetch(detail.field, detail.field), "created_at" => detail.verified_at)
        [row, detail.verified_at, "verification", detail.id]
      end)
    end

    entries.sort_by { |_, time, type, id| [-time.to_r, type, -id] }
  end

  def scoped_visits
    @appointment_id ? @visits.where(appointment_id: @appointment_id) : @visits
  end

  def visible_appointment_id(visit)
    visit.appointment_id if visit && visit.clinic_id == @clinic.id && visit.patient_id == @patient.id
  end

  def paginate(scope, type, time_column: :created_at)
    if @before
      timestamp, previous_type, id = @before
      earlier = scope.where(time_column => ...timestamp)
      earlier = earlier.or(scope.where(time_column => timestamp)) if type > previous_type
      if type == previous_type
        earlier = earlier.or(scope.where(time_column => timestamp, id: ...id))
      end
      scope = earlier
    end

    scope.order(time_column => :desc, id: :desc).limit(PAGE_SIZE + 1)
  end
end

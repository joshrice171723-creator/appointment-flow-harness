class OperationsQuery
  COUNTS = %w[total completed canceled rescheduled unknown messaged replied patient_confirmed].freeze
  FOLLOW_UP_COUNTS = %w[
    missing_birthdate missing_phone invalid_phone guardian_visits contact no_response delivery
    patient ambiguous_reply other resolved open total decline_replies affirmative_review
  ].freeze

  def self.call(now: Time.current, month: nil)
    new(now, month).call
  end

  def initialize(now, month)
    @now = now
    @detail_month = month == "current" ? now.utc.strftime("%Y-%m") : month
    @detail_start = Date.iso8601("#{@detail_month}-01") if @detail_month
    @contact_policy = ContactPolicy.new(now)
    @rows = {}
    @clinics = Clinic.includes(:setting, :reporting_zone).index_by(&:id)
    @zones = @clinics.transform_values do |clinic|
      Time.find_zone(clinic.setting&.timezone || clinic.reporting_zone&.timezone)
    end
  end

  def call
    count_appointments
    count_patient_fields
    outreach_by_revision = message_outreach_by_revision
    current_revisions = Appointment.where(id: outreach_by_revision.keys.map(&:first))
      .pluck(:id, :patient_id, :clinic_id, :start_at, :status)
      .to_h { |id, patient_id, clinic_id, start_at, status| [[id, patient_id, clinic_id, start_at], status] }

    # Moved or removed visits keep their message history in the original clinic and month.
    outreach_by_revision.each do |revision, outreach|
      _appointment_id, _patient_id, clinic_id, start_at = revision
      recorded = reportable?(clinic_id: clinic_id, start_at: start_at, status: current_revisions[revision])
      next unless current_revisions.key?(revision) || recorded

      row = row_for(clinic_id: clinic_id, start_at: start_at)
      count_outreach(row, outreach, recorded: recorded)
    end

    count_follow_up_issues
    clinics = @clinics.values.sort_by(&:name).map do |clinic|
      {
        "id" => clinic.id,
        "name" => clinic.name,
        "messaging_available" => clinic.setting.present?
      }
    end
    rows = @rows.values.sort_by do |row|
      [-Date.parse(row["outcome_month"] + "-01").jd, row["clinic"]]
    end

    OperationsSerializer.new(
      rows: rows.map do |row|
        row.fetch("reply_events").each_value { |event| count_review_reply(row.fetch("follow_up"), event) }
        row.merge("messages_sent" => row.fetch("message_ids").size)
      end,
      clinics: clinics,
      month: @now.utc.to_date.beginning_of_month
    ).as_json
  end

  private

  def detailed?(start_at)
    @detail_month.nil? || start_at.strftime("%Y-%m") == @detail_month
  end

  def count_appointments
    month = :start_month
    # Future-only months still belong in the month picker.
    Appointment.distinct.pluck(:clinic_id, month).each do |clinic_id, start_at|
      row_for(clinic_id: clinic_id, start_at: start_at)
    end

    recorded = Appointment.where(status: Appointment::OUTCOMES.keys)
    @zones.each do |clinic_id, zone|
      next unless zone

      elapsed = elapsed_appointments(clinic_id, zone)
      recorded = recorded.or(elapsed)
    end
    recorded.group(:clinic_id, month, :status).count.each do |(clinic_id, start_at, status), count|
      row = row_for(clinic_id: clinic_id, start_at: start_at)
      row["total"] += count
      row[Appointment::OUTCOMES.fetch(status, "unknown")] += count
    end
  end

  def elapsed_appointments(clinic_id, zone)
    scope = Appointment.for_clinic(clinic_id)
    local_now = @now.in_time_zone(zone)
    wall_now = Time.utc(local_now.year, local_now.month, local_now.day,
      local_now.hour, local_now.min, local_now.sec + local_now.subsec)
    elapsed = scope.where(start_at: ..wall_now)
    # Match PostgreSQL's standard-time interpretation of skipped and repeated wall times.
    zone.tzinfo.transitions_up_to(@now + 2.days, @now - 2.days).each do |transition|
      previous = transition.previous_offset.utc_total_offset
      following = transition.offset.utc_total_offset
      next if previous == following
      instant = transition.at.to_time.utc
      affected = [instant + previous, instant + following].min...[instant + previous, instant + following].max
      offset = following < previous ? following : previous
      elapsed = elapsed.where.not(start_at: affected)
        .or(scope.where(start_at: affected).where(start_at: ..(@now.utc + offset)))
    end
    elapsed
  end

  def count_patient_fields
    appointments = Appointment.joins(:patient)
    appointments = appointments.within_window(@detail_start, @detail_start.next_month) if @detail_start
    appointments.group(
      "pms.appointments.clinic_id", :start_month,
      "pms.patients.missing_birthdate", "pms.patients.phone_quality"
    ).count.each do |(clinic_id, start_at, missing_birthdate, phone_quality), count|
      counts = row_for(clinic_id: clinic_id, start_at: start_at).fetch("follow_up")
      counts["missing_birthdate"] += count if missing_birthdate
      if phone_quality == "missing"
        counts["missing_phone"] += count
      elsif phone_quality == "invalid"
        counts["invalid_phone"] += count
      end
    end
  end

  def message_outreach_by_revision
    outreach_by_revision = {}
    events_by_message = ActivityEvent.where(message_id: Message.sent.select(:id), actor: "Patient",
      kind: %w[confirmation reply ambiguous_reply late_reply])
      .select(:id, :message_id, :visit_id, :kind, :body, :case_id).group_by(&:message_id)
    sent_items = MessageItem.joins(:message, :visit).merge(Message.sent).distinct.pluck(
      "desk.visits.appointment_id", "desk.visits.patient_id", "desk.visits.clinic_id",
      "desk.visits.start_at", "desk.visits.id", "desk.messages.id", "desk.messages.recipient_id"
    )
    sent_items.each do |appointment_id, patient_id, clinic_id, start_at, visit_id, message_id, recipient_id|
      revision = [appointment_id, patient_id, clinic_id, start_at]
      outreach = outreach_by_revision[revision] ||= {
        message_ids: Set.new, reply_events: {}, replied: false, confirmed: false, guardian: false
      }
      outreach.fetch(:message_ids).add(message_id)
      include_details = detailed?(start_at)
      if include_details
        outreach[:guardian] ||= recipient_id.present? && recipient_id != patient_id
      end
      events_by_message.fetch(message_id, []).each do |event|
        if include_details && %w[reply ambiguous_reply late_reply].include?(event.kind) &&
           (event.visit_id.nil? || event.visit_id == visit_id)
          outreach.fetch(:reply_events)[event.id] = event
        end
        next unless event.visit_id == visit_id

        outreach[:replied] = true if %w[confirmation reply].include?(event.kind)
        outreach[:confirmed] = true if event.kind == "confirmation"
      end
    end
    outreach_by_revision
  end

  def count_follow_up_issues
    issues = FollowUpIssue.all
    if @detail_start
      # Keep months represented only by older issues in the comparison.
      issues.joins(:visit).distinct.pluck("desk.visits.clinic_id", "desk.visits.start_month")
        .each { |clinic_id, start_at| row_for(clinic_id: clinic_id, start_at: start_at) }
      visits = Visit.within_window(@detail_start, @detail_start.next_month)
      issues = issues.where(visit_id: visits.select(:id))
    end
    issues.joins(:visit).left_joins(:resolution_event).group(
      "desk.visits.clinic_id", "desk.visits.start_month",
      :code, :reason_code, :resolved, "desk.events.kind"
    ).count.each do |(clinic_id, start_at, code, reason_code, resolved, resolution_kind), count|
      row = row_for(clinic_id: clinic_id, start_at: start_at)
      counts = row.fetch("follow_up")
      category = %w[contact no_response delivery patient ambiguous_reply].include?(code) ? code : "other"
      counts[category] += count
      counts["total"] += count
      counts[resolved ? "resolved" : "open"] += count
      if code == "contact"
        reason = reason_code.presence || "other"
        holds = row.fetch("contact_holds")[reason] ||= { "open" => 0, "appointment_outcome" => 0, "otherwise_resolved" => 0 }
        resolution = if !resolved
          "open"
        elsif %w[confirmed rescheduled canceled].include?(resolution_kind)
          "appointment_outcome"
        else
          "otherwise_resolved"
        end
        holds[resolution] += count
      end
    end
  end

  def count_review_reply(counts, event)
    text = event.body.to_s
    classification = ReplyClassification.call(text)
    had_follow_up = event.case_id.present? || event.kind == "ambiguous_reply"
    counts["decline_replies"] += 1 if had_follow_up && classification == :decline
    counts["affirmative_review"] += 1 if had_follow_up && ReplyClassification.affirmative_lead?(text)
  end

  def reportable?(clinic_id:, start_at:, status: nil)
    return true if Appointment::OUTCOMES.key?(status)

    zone = @zones.fetch(clinic_id)
    return false unless zone

    # PostgreSQL resolves a repeated wall time using standard time.
    zone.tzinfo.local_to_utc(start_at, false) <= @now
  rescue TZInfo::PeriodNotFound
    zone.local(
      start_at.year, start_at.month, start_at.day,
      start_at.hour, start_at.min, start_at.sec + start_at.subsec
    ) <= @now
  end

  def row_for(clinic_id:, start_at:)
    month = start_at.strftime("%Y-%m")
    @rows[[clinic_id, month]] ||= COUNTS.index_with(0).merge(
      "clinic_id" => clinic_id,
      "clinic" => @clinics.fetch(clinic_id).name,
      "outcome_month" => month,
      "message_ids" => Set.new,
      "reply_events" => {},
      "contact_holds" => {},
      "follow_up" => FOLLOW_UP_COUNTS.index_with(0)
    )
  end

  def count_outreach(row, outreach, recorded: true)
    row.fetch("reply_events").merge!(outreach.fetch(:reply_events))
    row.fetch("follow_up")["guardian_visits"] += 1 if outreach.fetch(:guardian)
    return unless recorded

    row.fetch("message_ids").merge(outreach.fetch(:message_ids))
    row["messaged"] += 1
    row["replied"] += 1 if outreach.fetch(:replied)
    row["patient_confirmed"] += 1 if outreach.fetch(:confirmed)
  end
end

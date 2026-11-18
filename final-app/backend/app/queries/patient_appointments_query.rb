class PatientAppointmentsQuery
  def initialize(patient, clinic, now: Time.current)
    @patient = patient
    @clinic = clinic
    @now = now
    @appointments = Appointment.for_clinic(clinic.id).where(patient_id: patient.id)
    @visits = Visit.for_clinic(clinic.id).for_patient(patient.id)
    @policy = ContactPolicy.new(now)
  end

  def next_appointment
    @appointments.scheduled.where(start_at: clinic_wall_time..).where.not(start_at: clinic_wall_time).chronological.first
  end

  def page(filter:, before:, limit:, appointment_id: nil)
    source = @appointments
    tracked = AppointmentHistory.where(patient_id: @patient.id, clinic_id: @clinic.id)
      .where.not(appointment_id: @appointments.select(:id))
    source = source.where(id: appointment_id) if appointment_id
    tracked = tracked.where(appointment_id: appointment_id) if appointment_id

    # Each tracked booking has one latest time. A source row always takes precedence.
    if before
      time, id = before
      tracked = tracked.where(start_at: ...time).or(tracked.where(start_at: time, appointment_id: ...id))
      source = source.where(start_at: ...time).or(source.where(start_at: time, id: ...id))
    end
    source = filter_dates(source, filter)
    tracked = filter_dates(tracked, filter)
    source_rows = source.order(start_at: :desc, id: :desc).limit(limit).pluck(:id, :start_at)
    history_rows = tracked.order(start_at: :desc, appointment_id: :desc).limit(limit).pluck(:appointment_id, :start_at)
    (source_rows + history_rows).sort_by { |id, time| [-time.to_r, -id] }.first(limit)
  end

  def rows(ids)
    appointments = @appointments.where(id: ids).index_by(&:id)
    visits = @visits.where(appointment_id: ids).with_context.order(id: :desc).to_a
    visit_ids = visits.map(&:id)
    revisions = visits.group_by(&:appointment_id)
    issues = FollowUpIssue.group_by_visit(FollowUpIssue.open.for_visits(visit_ids).order(:id))
    pending = ActivityEvent.pms_change.where(visit_id: visit_ids).distinct.pluck(:visit_id).to_set
    replies = latest_patient_replies(visit_ids)

    ids.filter_map do |id|
      versions = revisions.fetch(id, [])
      appointment = appointments[id]
      visit = if appointment
        versions.find { |version| version.matches_appointment?(appointment) && version.current } ||
          (versions.find { |version| version.matches_appointment?(appointment) } unless appointment.status == "scheduled")
      else
        versions.first
      end
      next unless appointment || visit

      # A replacement booking belongs to its own patient and clinic. Keep the old visit facts separate.
      row = AppointmentSerializer.new(appointment: appointment, visit: visit,
        hold: visit && outreach_for(visit, pending: pending.include?(visit.id)).fetch(:hold),
        issues: issues.fetch(visit&.id, []), patient_reply: replies[visit&.id]).as_json
      [id, row.merge("revisions" => versions.map do |version|
        version.attributes.slice("id", "start_at", "current", "confirmed_at", "confirmed_by")
      end)]
    end.to_h
  end

  def next_outreach(appointment, permission)
    return { hold: nil, allowed_channels: [] } unless appointment

    visit = @visits.current.find_by(appointment_id: appointment.id)
    if visit&.matches_appointment?(appointment)
      return outreach_for(visit, pending: visit.pending_pms_change?)
    end

    visit = Visit.new(patient: @patient, appointment: appointment, clinic_id: @clinic.id,
      clinic_setting: @clinic.setting, start_at: appointment.start_at)
    visit.contact_permission = permission if permission
    outreach_for(visit)
  end

  private

  def latest_patient_replies(visit_ids)
    reply_ids = ActivityEvent.where(visit_id: visit_ids, actor: "Patient", kind: "reply").group(:visit_id).maximum(:id)
    ActivityEvent.where(id: reply_ids.values).index_by(&:visit_id)
  end

  def after(scope, time)
    scope.where(start_at: time..).where.not(start_at: time)
  end

  def filter_dates(scope, filter)
    return after(scope, clinic_wall_time) if filter == "upcoming"
    return scope.where(start_at: ..clinic_wall_time) if filter == "past"
    scope
  end

  def outreach_for(visit, pending: false)
    return { hold: "Awaiting PMS update. Reminders paused for this time.", allowed_channels: [] } if pending
    return { hold: nil, allowed_channels: [] } unless visit.starts_at_utc.nil? || visit.starts_at_utc > @now

    @opt_outs ||= OptOut.where(clinic_id: @clinic.id).pluck(:destination).to_set
    decision = @policy.decision(visit, opt_outs: @opt_outs)
    { hold: decision.reason, allowed_channels: decision.destinations.keys }
  end

  def clinic_wall_time
    @now.in_time_zone(@clinic.setting.timezone).strftime("%F %T.%6N")
  end
end

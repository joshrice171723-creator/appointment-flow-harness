class AppointmentsQuery
  def initialize(clinic, date: nil, now: Time.current)
    @clinic_id = clinic.id
    @date = date
    @now = now
    @contact_policy = ContactPolicy.new(now)
  end

  def call
    visits = Visit.current.for_clinic(@clinic_id)
    if @date
      week = @date.beginning_of_week
      appointments = Appointment.for_clinic(@clinic_id).within_window(week, week + 7)
      visits = visits.where(appointment_id: appointments.select(:id))
    end

    current_visits = visits.chronological.with_messaging_context.to_a
    visit_ids = current_visits.map(&:id)
    @issues = FollowUpIssue.open.for_clinic(@clinic_id).where(visit_id: visit_ids).order(:id).group_by(&:visit_id)
    @pending_changes = visits.where(id: visit_ids).with_pending_pms_change.pluck(:id).to_set
    @opt_outs = OptOut.where(clinic_id: @clinic_id).pluck(:destination).to_set
    return calendar_visits(appointments, current_visits) if appointments

    current_visits.filter_map do |visit|
      next if past?(visit)

      AppointmentSerializer.new(visit: visit, hold: hold_reason(visit), issues: visible_issues(visit)).as_json
    end
  end

  private

  def hold_reason(visit)
    return "Awaiting PMS update. Reminders paused for this time." if @pending_changes.include?(visit.id)
    return if past?(visit)

    decision = @contact_policy.decision(visit, opt_outs: @opt_outs)
    return "No automated contact permission." if decision.reason_code == :permission

    decision.reason
  end

  def past?(visit)
    starts_at = visit.starts_at_utc
    starts_at && starts_at <= @now
  end

  def visible_issues(visit)
    @issues.fetch(visit.id, []) if visit.patient
  end

  def calendar_visits(appointments, current_visits)
    active = current_visits.index_by(&:appointment_id)
    appointments.chronological.includes(:patient, visits: [:events, :appointment, :patient]).map do |appointment|
      matching = appointment.visits.select do |visit|
        visit.matches_appointment?(appointment) && (appointment.status != "scheduled" || visit.current)
      end
      history = matching.max_by { |visit| [visit.current ? 1 : 0, visit.id] }
      reply = history&.latest_patient_reply
      current = active[appointment.id]
      current = nil unless current&.matches_appointment?(appointment)
      AppointmentSerializer.new(
        appointment: appointment, visit: current || history, patient_reply: reply,
        hold: current && hold_reason(current), issues: current ? visible_issues(current) : []
      ).as_json
    end
  end
end

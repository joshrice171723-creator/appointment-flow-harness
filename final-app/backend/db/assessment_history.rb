require "zlib"

# Setup replays closed months with local delivery. Only the app cache temporarily
# shows the appointments as scheduled. The outer setup transaction owns all writes.
class AssessmentHistory
  OUTCOMES = { "complete" => "confirmed", "broken" => "rescheduled", "unscheduled" => "canceled" }.freeze
  REVIEW_CODES = %w[patient ambiguous_reply].freeze

  def initialize(launch:, now:)
    @launch = launch
    @now = now
  end

  def replay
    ClinicSetting.find_each do |setting|
      staff = StaffMember.where(clinic_id: setting.clinic_id).order(:id).first
      next unless staff

      replay_clinic(setting, staff)
    end
  end

  private

  def replay_clinic(setting, staff)
    zone = Time.find_zone!(setting.timezone)
    end_day = @now.in_time_zone(zone).to_date.beginning_of_month
    return if end_day <= @launch

    clinic_id = setting.clinic_id
    existing_patients = Visit.for_clinic(clinic_id).select(:patient_id)
    appointments = Appointment.for_clinic(clinic_id).within_window(@launch, end_day)
      .where(status: OUTCOMES.keys).where.not(patient_id: existing_patients).chronological.to_a
    return if appointments.empty?

    final_statuses = appointments.to_h { |appointment| [appointment.id, appointment.status] }
    appointments_by_day = appointments.group_by { |appointment| appointment.start_at.to_date }
    Appointment.where(id: final_statuses.keys).update_all(status: "scheduled")
    appointments.each { |appointment| appointment.status = "scheduled" }

    (@launch...end_day).each do |day|
      last_due_day = day + ReminderSchedule::INITIAL_DAYS_BEFORE
      upcoming_ids = (day..last_due_day).flat_map do |due_day|
        appointments_by_day.fetch(due_day, []).map(&:id)
      end
      next if upcoming_ids.empty?

      at = zone.local(day.year, day.month, day.day, ReminderSchedule::REMINDER_HOUR)
      flow = ReminderFlow.new(now: at)
      new_days = day == @launch ? (@launch..last_due_day) : [last_due_day]
      reconciliation = ReconcileAppointments.new(now: at)
      new_days.each do |due_day|
        appointments_by_day.fetch(due_day, []).each do |appointment|
          reconciliation.reconcile_appointment(appointment, clinic_id: clinic_id)
        end
      end

      visits = Visit.current.for_clinic(clinic_id).where(appointment_id: upcoming_ids).chronological.with_context.to_a
      flow.reminder_sender.call(visits: visits, clinic_id: clinic_id, send_reminders: true)
      reply_to_reminders(visits, final_statuses, at)
      resolve_reply_work(visits, final_statuses, staff, at + 90.minutes)

      appointments_by_day.fetch(day, []).each do |appointment|
        appointment.status = final_statuses.fetch(appointment.id)
        Appointment.where(id: appointment.id).update_all(status: appointment.status)
        recorded_at = appointment.updated_at && Visit.clinic_wall_time_to_utc(appointment.updated_at, setting.timezone)
        ReconcileAppointments.new(now: recorded_at || at + 8.hours).reconcile_appointment(appointment, clinic_id: clinic_id)
      end
    end
  end

  def reply_to_reminders(visits, final_statuses, at)
    visits_by_id = visits.index_by(&:id)
    items = MessageItem.where(visit_id: visits_by_id.keys, purpose: %w[initial backup])
      .joins(:message).merge(Message.sent.where(created_at: at)).includes(:message).order(:message_id)
    receiver = ReceiveReply.new(now: at + 1.hour)
    items.each do |item|
      visit = visits_by_id.fetch(item.visit_id)
      next if visit.starts_at_utc <= at + 90.minutes

      status = final_statuses.fetch(visit.appointment_id)
      bucket = Zlib.crc32("reply-#{visit.appointment_id}") % 100
      next if status == "complete" && bucket < 12

      waits_for_email = bucket.between?(12, 29) && item.message.channel == "SMS" &&
        visit.start_at.to_date - at.to_date >= ReminderSchedule::INITIAL_DAYS_BEFORE
      next if waits_for_email
      next if item.purpose == "backup" && !bucket.between?(12, 29)

      text = if status != "complete"
        bucket.even? ? "NO" : "No, I can't make it."
      elsif bucket < 77
        bucket.even? ? "YES" : "Yeah!"
      else
        "Please call me about this appointment."
      end
      receiver.reply(visit: visit, text: text, receipt: item.message,
        request_key: "assessment-reply-#{visit.appointment_id}")
    end
  end

  def resolve_reply_work(visits, final_statuses, staff, at)
    visits_by_id = visits.index_by(&:id)
    FollowUpIssue.open.where(visit_id: visits_by_id.keys, code: REVIEW_CODES).order(:id).each do |issue|
      next unless issue.reload.resolved_at.nil?

      visit = visits_by_id.fetch(issue.visit_id)
      follow_up = issue.follow_up_case
      record_action(follow_up, staff, at, "claim") unless follow_up.owner_id
      outcome = OUTCOMES.fetch(final_statuses.fetch(visit.appointment_id))
      note = case outcome
             when "confirmed" then "Called the patient and confirmed the appointment."
             when "rescheduled" then "Called the patient and arranged a new appointment time."
             when "canceled" then "Called the patient and confirmed the cancellation."
             end
      if issue.reply_event_id
        result = RecordFollowUp.new(outcome: "clarified", version: follow_up.reload.version,
          issue_id: issue.id, note: note, appointment_ids: [visit.appointment_id])
          .record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: at)
        raise ReminderFlow::Conflict, result.fetch(:error) if result.key?(:error)
        issue = follow_up.issues.open.find_by!(visit_id: visit.id, code: "patient", reply_event_id: nil)
      end
      record_action(follow_up, staff, at + 1.minute, outcome, issue_id: issue.id, note: note)
    end
  end

  def record_action(follow_up, staff, at, outcome, issue_id: nil, note: nil)
    action = RecordFollowUp.new(outcome: outcome, version: follow_up.reload.version, issue_id: issue_id, note: note)
    result = action.record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: at)
    raise ReminderFlow::Conflict, result.fetch(:error) if result.key?(:error)
  end
end

# Assessment setup only. Patient details come from the replica throughout.
# Replay exposes the earlier scheduled appointment state in the app cache.
class AssessmentTaskExamples
  SCENARIOS = {
    missing_birthdate: "contact",
    guardian: "contact",
    missing_phone: "contact",
    invalid_phone: "contact",
    language: "contact",
    permission: "contact",
    opt_out: "contact",
    appointment_time: "contact",
    delivery: "delivery",
    no_response: "no_response",
    decline: "patient",
    call_me: "patient",
    ambiguous: "ambiguous_reply"
  }.freeze
  NOVEMBER_FOLLOW_UPS = %i[missing_birthdate invalid_phone permission delivery].freeze
  PMS_OUTCOMES = { "confirmed" => "complete", "rescheduled" => "broken", "canceled" => "unscheduled" }.freeze
  REPLIES = {
    opt_out: "STOP", decline: "NO", call_me: "Yes, but please call me.", ambiguous: "YES"
  }.freeze
  Example = Data.define(:scenario, :code, :cohort) do
    def source_note
      "Assessment task: #{scenario} (#{cohort})"
    end
  end

  class FailedDelivery
    def deliver(...)
      ["failed", nil]
    end
  end

  def self.examples
    tasks = SCENARIOS.flat_map do |scenario, code|
      rows = [Example.new(scenario, code, :open), Example.new(scenario, code, :launch_month)]
      rows << Example.new(scenario, code, :next_month) if NOVEMBER_FOLLOW_UPS.include?(scenario)
      rows
    end
    tasks + [Example.new(:authorized_guardian, nil, :launch_month)]
  end

  def self.seed_replica(now:, clinics:, launch:)
    ReplicaSeed::Record.transaction do
      clinics.each do |clinic|
        clinic_id = clinic.fetch("id")
        local_now = now.in_time_zone(clinic.fetch("timezone"))
        existing_notes = ReplicaSeed::Appointment.where(clinic_id: clinic_id).pluck(:procedure_note).to_set
        examples.each do |example|
          next if existing_notes.include?(example.source_note)

          start = appointment_time(example, local_now, launch)
          next unless start

          create_source_example(example, clinic_id, start)
        end
      end
    end
  end

  def self.appointment_time(example, now, launch)
    if example.cohort == :open
      slot = SCENARIOS.keys.index(example.scenario)
      day = now.to_date + 1 + slot % 4
      hour = [9, 11, 13, 15, 16].fetch(slot % 5)
      if example.scenario == :appointment_time
        day = now.to_date
        day += 1 until day.sunday?
        hour = 15
        day += 7 if day == now.to_date && now.hour >= hour
      elsif example.scenario == :no_response
        soon = now + 36.hours
        day = soon.to_date
        hour = soon.hour
        if day.sunday?
          day -= 1
          hour = 23
        end
      else
        day += 1 if day.sunday?
      end
    else
      month = example.cohort == :launch_month ? launch : launch.next_month.beginning_of_month
      offset = example.cohort == :launch_month ? 7 + (SCENARIOS.keys.index(example.scenario) || SCENARIOS.size) :
        2 + NOVEMBER_FOLLOW_UPS.index(example.scenario)
      day = month + offset
      if example.scenario == :appointment_time
        day += 1 until day.sunday?
      else
        day += 1 if day.sunday?
      end
      return if day >= now.to_date

      hour = 15
    end
    Time.utc(day.year, day.month, day.day, hour)
  end

  def self.create_source_example(example, clinic_id, start)
    historical = example.cohort != :open
    if %i[guardian authorized_guardian].include?(example.scenario)
      guardian_id = ReplicaSeed::Patient.maximum(:id).to_i + 1
      ReplicaSeed::Patient.create!(id: guardian_id, **ReplicaSeed.patient_name(guardian_id),
        birthdate: Date.new(1980, 1, 1), wireless_phone: phone(guardian_id), preferred_language: "en")
    end

    id = ReplicaSeed::Patient.maximum(:id).to_i + 1
    fields = {
      id: id, **ReplicaSeed.patient_name(id),
      birthdate: guardian_id ? start.to_date.years_ago(12) : Date.new(1988, 1, 1),
      guarantor_id: guardian_id, wireless_phone: phone(id), preferred_language: "en"
    }
    fields.merge!(contact_problem(example.scenario))
    ReplicaSeed::Patient.create!(fields)

    starts = example.scenario == :ambiguous ? [start - 1.hour, start] : [start]
    first_appointment_id = ReplicaSeed::Appointment.maximum(:id).to_i + 1
    starts.each_with_index do |at, index|
      status = historical ? PMS_OUTCOMES.fetch(appointment_outcome(example.scenario, index)) : "scheduled"
      ReplicaSeed::Appointment.create!(id: first_appointment_id + index, patient_id: id, clinic_id: clinic_id,
        procedure_note: example.source_note,
        start_at: at, length_minutes: 30, status: status, provider_name: "Dr. Jordan Patel",
        updated_at: historical ? at + 1.hour : at - 7.days)
    end
  end

  def self.appointment_outcome(scenario, index)
    return "rescheduled" if scenario == :appointment_time
    return "canceled" if scenario == :decline || (scenario == :ambiguous && index == 1)

    "confirmed"
  end

  def self.contact_problem(scenario)
    case scenario
    when :missing_birthdate then { birthdate: nil }
    when :missing_phone then { wireless_phone: nil }
    when :invalid_phone then { wireless_phone: "Old number: 512-555-0100" }
    when :language then { preferred_language: "fr" }
    when :opt_out then { email: nil }
    else {}
    end
  end

  def self.phone(id)
    format("(737) 556-%04d", id % 10_000)
  end

  def initialize(now:)
    @now = now
  end

  def replay
    ClinicSetting.find_each do |setting|
      staff = StaffMember.where(clinic_id: setting.clinic_id).order(:id).first
      next unless staff

      examples = self.class.examples
      appointments = Appointment.for_clinic(setting.clinic_id).where(procedure_note: examples.map(&:source_note))
        .chronological.group_by(&:procedure_note)
      patient_ids = appointments.values.map { |visits| visits.first.patient_id }
      tracked_ids = Visit.for_clinic(setting.clinic_id).where(patient_id: patient_ids).distinct.pluck(:patient_id).to_set

      examples.each do |example|
        records = appointments[example.source_note]
        next if records.blank? || tracked_ids.include?(records.first.patient_id)

        replay_example(example, records, setting, staff)
      end
    end
  end

  private

  def replay_example(example, appointments, setting, staff)
    historical = example.cohort != :open
    clinic_id = setting.clinic_id
    final_statuses = appointments.to_h { |appointment| [appointment.id, appointment.status] }
    Appointment.where(id: final_statuses.keys).update_all(status: "scheduled") if historical

    visits = reconcile(final_statuses.keys, clinic_id, @now)
    first = visits.first
    return if !historical && first.starts_at_utc && first.starts_at_utc <= @now

    send_at = historical ? first.reminder_at(days_before: ReminderSchedule::INITIAL_DAYS_BEFORE) : delivery_time(setting)
    if example.scenario == :permission
      first.contact_permission.update!(sms: false, email: false)
      visits = reload_visits(visits)
    elsif example.scenario == :authorized_guardian
      first.contact_permission.update!(authorized_guarantor_id: first.patient.guarantor_id)
      visits = reload_visits(visits)
      run_batch(visits, at: send_at)
      receipt = visits.first.messages.sent.first!
      unless receipt.recipient_id == first.patient.guarantor_id
        raise ReminderFlow::Conflict, "The guardian example did not reach the authorized adult."
      end
      receive_reply(visits.first, receipt, "YES", at: send_at + 5.minutes, stage: "guardian")
      finish_history(appointments, final_statuses, setting)
      return
    end
    hold_at = historical ? send_at + 15.minutes : @now
    if example.code == "contact" && example.scenario != :opt_out
      run_batch(visits, at: hold_at, send_reminders: false)
    else
      transport = example.scenario == :delivery ? FailedDelivery.new : ReminderFlow::FakeSender.new
      run_batch(visits, at: send_at, transport: transport)
      if (text = REPLIES[example.scenario])
        receive_reply(first, first.messages.sent.first!, text, at: send_at + 5.minutes, stage: "initial")
      end
      if example.scenario == :no_response
        hold_at = first.reminder_at(days_before: 1) if historical
        run_batch(visits, at: hold_at, send_reminders: false)
      elsif example.scenario == :opt_out
        run_batch(visits, at: hold_at, send_reminders: false)
      end
    end

    issues = FollowUpIssue.open.where(visit_id: visits.map(&:id), code: example.code).order(:id).to_a
    raise ReminderFlow::Conflict, "Assessment example did not create #{example.code} work for patient #{first.patient_id}." if issues.empty?
    unless historical
      if %i[decline call_me].include?(example.scenario)
        record_issue_action(issues.first, staff, "attempted", at: send_at + 10.minutes)
      end
      return
    end

    issues.each do |issue|
      index = appointments.index { |appointment| appointment.id == issue.visit.appointment_id }
      outcome = self.class.appointment_outcome(example.scenario, index)
      record_issue_action(issue, staff, outcome, at: hold_at + 30.minutes)
    end
    if FollowUpIssue.open.exists?(id: issues.map(&:id))
      raise ReminderFlow::Conflict, "Assessment example did not handle #{example.code} work for patient #{first.patient_id}."
    end

    FollowUpIssue.open.where(visit_id: visits.map(&:id), code: "patient", reply_event_id: nil).each do |item|
      index = appointments.index { |appointment| appointment.id == item.visit.appointment_id }
      record_issue_action(item, staff, self.class.appointment_outcome(example.scenario, index), at: hold_at + 31.minutes)
    end
    finish_history(appointments, final_statuses, setting)
  end

  def finish_history(appointments, final_statuses, setting)
    final_statuses.each { |id, status| Appointment.where(id: id).update_all(status: status) }
    recorded_at = Visit.clinic_wall_time_to_utc(appointments.last.updated_at, setting.timezone)
    reconcile(final_statuses.keys, setting.clinic_id, recorded_at)
  end

  def reconcile(ids, clinic_id, at)
    reconciliation = ReconcileAppointments.new(now: at)
    Appointment.where(id: ids).each { |appointment| reconciliation.reconcile_appointment(appointment, clinic_id: clinic_id) }
    Visit.current.where(appointment_id: ids).chronological.with_context.to_a
  end

  def reload_visits(visits)
    Visit.where(id: visits.map(&:id)).chronological.with_context.to_a
  end

  def delivery_time(setting)
    local_now = @now.in_time_zone(setting.timezone)
    at = local_now.change(hour: ReminderSchedule::REMINDER_HOUR, min: 0, sec: 0, usec: 0)
    at > local_now - 15.minutes ? at - 1.day : at
  end

  def run_batch(visits, at:, send_reminders: true, transport: ReminderFlow::FakeSender.new)
    flow = ReminderFlow.new(now: at, sender: transport)
    flow.reminder_sender.call(visits: visits, clinic_id: visits.first.clinic_id, send_reminders: send_reminders)
  end

  def receive_reply(visit, receipt, text, at:, stage:)
    ReceiveReply.new(now: at).reply(visit: visit, text: text, receipt: receipt,
      request_key: "assessment-task-#{visit.appointment_id}-#{stage}")
  end

  def record_issue_action(issue, staff, outcome, at:)
    follow_up = issue.follow_up_case
    actions = []
    actions << { outcome: "claim" } unless follow_up.owner_id
    note = case outcome
           when "attempted" then "Called the patient and left a callback number."
           when "canceled" then "Spoke with the patient and recorded the cancellation."
           when "rescheduled" then "Recorded the new scheduling outcome after speaking with the patient."
           else "Confirmed the appointment in person at the front desk."
           end
    if issue.reply_event_id
      candidate_ids = Visit.where(id: issue.candidate_visit_ids).pluck(:appointment_id)
      actions << { outcome: outcome == "attempted" ? "unclear" : "clarified", issue_id: issue.id,
        note: note, appointment_ids: candidate_ids }
    else
      actions << { outcome: outcome, issue_id: issue.id, note: note }
    end
    actions.each do |action|
      result = RecordFollowUp.new(version: follow_up.reload.version, **action)
        .record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: at)
      raise ReminderFlow::Conflict, result.fetch(:error) if result.key?(:error)
    end
  end
end

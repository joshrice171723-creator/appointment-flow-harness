require "digest"

class DemoState < ApplicationRecord
  self.table_name = "desk.demo"
end

# Consume the test failure flag across controller and worker transactions.
module TestDeliveryFailure
  def deliver(...)
    failed = DemoState.where(id: 1, fail_next: true).update_all(fail_next: false).positive?
    failed ? ["failed", nil] : super
  end
end
ReminderFlow::FakeSender.prepend(TestDeliveryFailure)

# Prepared records for tests that exercise workflows with existing history.
class WorkflowFixture
  def self.load(now: Time.current)
    new(now).load
  end

  def self.clear
    # Child records go first so reset respects the database's foreign keys.
    [AppointmentHistory, IssueCandidate, FollowUpIssue, ActivityEvent, MessageItem, Message, FollowUpCase, Visit,
     OptOut, ContactPermission, PatientDetailVerification, StaffMember, ClinicSetting, ReportingClinicZone,
     DemoState, SourceSync, Appointment, Patient, Clinic].each(&:delete_all)
  end

  def initialize(now)
    @now = now
    @contacts = ContactPolicy.new(now)
    @templates = MessageTemplates.new
  end

  def load
    @setting = ClinicSetting.create!(clinic_id: 1, timezone: "America/Chicago", sender: "+15125550100")
    ReportingClinicZone.create!(clinic_id: 1, timezone: "America/Chicago")
    ReportingClinicZone.create!(clinic_id: 5, timezone: "America/Phoenix")
    StaffMember.create!(id: 11, clinic_id: 1, name: "Taylor Morgan")
    StaffMember.create!(id: 12, clinic_id: 1, name: "Sam Rivera")
    guardians = {161 => 190, 167 => 191}
    permissions = Appointment.for_clinic(1).distinct.pluck(:patient_id).map do |patient_id|
      {patient_id: patient_id, clinic_id: 1, sms: true, email: true,
       authorized_guarantor_id: guardians[patient_id]}
    end
    ContactPermission.insert_all!(permissions)
    DemoState.create!(id: 1, seeded_at: @now, dataset: "apex-flow")
    seed_messages
    seed_incoming_reviews
    seed_resolved_confirmation
    seed_stop_reply
    ReminderFlow.new(now: @now).run(1, send_reminders: false)
    FollowUpIssue.index_visits(FollowUpIssue.all)
  end

  private

  def seed_messages
    examples = {
      102 => %w[SMS Email], 103 => ["Email"], 106 => ["SMS"], 107 => ["SMS"],
      110 => ["SMS"], 123 => ["SMS"], 22 => ["SMS"],
      23 => ["Email"], 26 => ["Email"]
    }
    permissions = ContactPermission.includes(:authorized_guarantor).index_by(&:patient_id)
    contacts = {}
    channels_by_appointment = {}
    visits = []
    Appointment.for_clinic(1).includes(:patient, :clinic).order(:start_at, :id).each do |appointment|
      contact = @contacts.recipient(patient: appointment.patient,
        permission: permissions.fetch(appointment.patient_id), timezone: "America/Chicago")
      next unless contact && @templates.message_language(contact.language)

      historical = appointment.status != "scheduled" || appointment.id == 109
      channels = historical ? [contact.phone ? "SMS" : "Email"] : examples.fetch(appointment.id, [])
      next if channels.empty?

      start_at = appointment.id == 110 ? appointment.start_at - 1.day : appointment.start_at
      revision_source = appointment.dup
      revision_source.id = appointment.id
      revision_source.start_at = start_at
      revision_source.status = "scheduled"
      visits << {appointment_id: appointment.id, patient_id: appointment.patient_id,
        clinic_id: appointment.clinic_id, revision: revision_source.confirmation_revision,
        start_at: start_at, current: appointment.status == "scheduled" && appointment.id != 110}
      contacts[appointment.id] = contact
      channels_by_appointment[appointment.id] = channels
    end

    # These are prepared examples, so save each table in one trip to PostgreSQL.
    # Keep real records for the shared contact rules and message templates.
    Visit.insert_all!(visits)
    visits = Visit.with_context.order(:start_at, :id).to_a
    AppointmentHistory.record_visits(visits)
    messages = []
    visits.each do |visit|
      contact = contacts.fetch(visit.appointment_id)
      channels_by_appointment.fetch(visit.appointment_id).each do |channel|
        destination = channel == "SMS" ? contact.phone : contact.email
        next unless destination

        purpose = visit.appointment_id == 102 && channel == "Email" ? "backup" : "initial"
        messages << {
          patient_id: visit.patient_id, clinic_id: 1, clinic_name: visit.clinic.name,
          sender: "+15125550100", channel: channel, destination: destination,
          body: @templates.message_body(visit, channel, ["initial"], language: contact.language),
          token: message_token(visit, channel),
          created_at: message_time(visit, days_before: purpose == "backup" ? 6 : 7),
          status: "sent", receipt: "fake-#{visit.appointment_id}-#{channel}", recipient_id: contact.id
        }
      end
    end
    Message.insert_all!(messages)
    messages_by_token = Message.all.index_by(&:token)
    items = visits.flat_map do |visit|
      channels_by_appointment.fetch(visit.appointment_id).filter_map do |channel|
        message = messages_by_token[message_token(visit, channel)]
        next unless message

        {message_id: message.id, visit_id: visit.id,
         purpose: visit.appointment_id == 102 && channel == "Email" ? "backup" : "initial"}
      end
    end
    MessageItem.insert_all!(items)
    seed_past_replies(visits, messages_by_token)
  end

  def message_token(visit, channel)
    Digest::MD5.hexdigest("demo-message-#{visit.appointment_id}#{channel}")
  end

  def message_time(visit, days_before:)
    zone = Time.find_zone!("America/Chicago")
    day = visit.start_at.to_date - days_before
    hour = visit.start_at.hour.clamp(10, 17)
    planned = zone.local(day.year, day.month, day.day, hour)
    today = @now.in_time_zone(zone)
    last_send_day = today.to_date - (today.hour < 10 ? 1 : 0)
    cap = zone.local(last_send_day.year, last_send_day.month, last_send_day.day, 10)
    [planned, cap].min
  end

  def seed_past_replies(visits, messages_by_token)
    confirmations = []
    patient_events = []
    staff_events = []
    cases_by_patient = {}
    issues = []
    visits.each do |visit|
      appointment = visit.appointment
      next if appointment.status == "scheduled" || appointment.id == 109

      message = messages_by_token[message_token(visit, "SMS")] || messages_by_token[message_token(visit, "Email")]
      next unless message

      declined = %w[broken unscheduled].include?(appointment.status)
      bucket = Digest::MD5.hexdigest("reply-#{appointment.id}")[0]
      next if !declined && %w[c d e f].include?(bucket)

      at = message.created_at + 2.hours
      if !declined && !%w[0 1].include?(bucket)
        visit.confirmed_at = at
        visit.confirmed_by = "Patient"
        confirmations << visit
        patient_events << {actor: "Patient", kind: "confirmation", body: "YES", created_at: at,
          visit_id: visit.id, message_id: message.id, case_id: nil}
        next
      end

      body = declined ? ["NO", "No, please call me.", "No, I need to check."][appointment.id % 3] : "Please call me."
      handled_at = at + 1.hour
      outcome = declined ? appointment.outcome : "confirmed"
      reason = if !declined
        "Called the patient, answered their question, and confirmed this visit."
      elsif outcome == "canceled"
        "Canceled after the patient declined."
      else
        "Rescheduled after the patient declined."
      end
      unless declined
        visit.confirmed_at = handled_at
        visit.confirmed_by = "Taylor Morgan"
        confirmations << visit
      end

      # Each past reply has already been handled. The live examples below still
      # exercise the normal follow-up workflow and incoming STOP handler.
      previous_case = cases_by_patient[visit.patient_id]
      cases_by_patient[visit.patient_id] = {patient_id: visit.patient_id, clinic_id: 1,
        state: "resolved", due_at: at, updated_at: handled_at,
        version: previous_case ? previous_case.fetch(:version) + 2 : 2}
      patient_events << {actor: "Patient", kind: "reply", body: body, created_at: at,
        visit_id: visit.id, message_id: message.id, case_id: nil}
      staff_events << {actor: "Taylor Morgan", kind: outcome, body: reason, created_at: handled_at,
        visit_id: visit.id, message_id: nil, case_id: nil}
      issues << {visit_id: visit.id, code: "patient", reason: "Patient replied: #{body}",
        created_at: at, resolved_at: handled_at}
    end

    unless confirmations.empty?
      Visit.upsert_all(confirmations.map { |visit| visit.attributes.except("start_month") }, unique_by: :id,
        update_only: [:confirmed_at, :confirmed_by])
    end
    unless cases_by_patient.empty?
      FollowUpCase.insert_all!(cases_by_patient.values)
      case_ids = FollowUpCase.pluck(:patient_id, :id).to_h
      visits_by_id = visits.index_by(&:id)
      (patient_events + staff_events).each do |event|
        next if event[:kind] == "confirmation"

        event[:case_id] = case_ids.fetch(visits_by_id.fetch(event.fetch(:visit_id)).patient_id)
      end
      issues.each do |issue|
        issue[:case_id] = case_ids.fetch(visits_by_id.fetch(issue.fetch(:visit_id)).patient_id)
      end
    end
    ActivityEvent.insert_all!(patient_events) unless patient_events.empty?
    unless staff_events.empty?
      resolutions = ActivityEvent.insert_all!(staff_events, returning: %w[id visit_id]).to_a
        .to_h { |event| [event.fetch("visit_id"), event.fetch("id")] }
      issues.each { |issue| issue[:resolution_event_id] = resolutions.fetch(issue.fetch(:visit_id)) }
      FollowUpIssue.insert_all!(issues)
    end
  end

  def seed_incoming_reviews
    {102 => ["SMS", "NO"], 23 => ["Email", "Maybe? Which visit is this for?"],
     26 => ["Email", "Yes, but call me."]}.each do |appointment_id, (channel, body)|
      visit = Visit.current.find_by(appointment_id: appointment_id)
      next unless visit && visit.starts_at_utc > @now

      message = visit.messages.find_by!(channel: channel)
      at = [message.created_at, @now - 1.hour].max
      case_id = FollowUpWorkflow.new(now: at).issue(visit, "patient", "Review patient reply: #{body}")
      ActivityEvent.record(actor: "Patient", kind: "reply", body: body, at: at,
        case_id: case_id, visit_id: visit.id, message_id: message.id)
    end
  end

  def seed_resolved_confirmation
    visit = Visit.find_by(appointment_id: 109)
    return unless visit

    zone = Time.find_zone!("America/Chicago")
    time = visit.start_at - 1.day
    at = zone.local(time.year, time.month, time.day, time.hour)
    visit.update!(confirmed_at: at, confirmed_by: "Patient")
    case_id = FollowUpWorkflow.new(now: at - 1.hour).issue(visit, "no_response", "Confirmation was needed. Patient replied YES.")
    event_id = ActivityEvent.record(actor: "Patient", kind: "confirmation", body: "YES", at: at,
      visit_id: visit.id, case_id: case_id, message_id: visit.messages.first.id)
    FollowUpWorkflow.new(now: at).close_visit_follow_ups(visit, "Patient replied YES.", event_id: event_id)
  end

  def seed_stop_reply
    receipt = Message.sent.where(channel: "SMS").where.not(patient_id: [102, 106, 107, 109, 110, 111, 161])
      .order(created_at: :desc, id: :desc).first
    return unless receipt

    ReceiveReply.new(now: @now).reply(visit: receipt.visits.first, text: "STOP", receipt: receipt, request_key: "seed-stop")
  end
end

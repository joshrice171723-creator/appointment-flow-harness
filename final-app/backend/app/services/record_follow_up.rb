class RecordFollowUp
  NOTE_LENGTH = (3..1000).freeze
  FINAL_OUTCOMES = %w[confirmed rescheduled canceled].freeze
  ISSUE_OUTCOMES = (["attempted"] + FINAL_OUTCOMES).freeze

  def initialize(outcome:, version:, issue_id: nil, note: nil, appointment_ids: nil)
    @outcome = outcome
    @version = version
    @issue_id = issue_id
    @note = note
    @appointment_ids = appointment_ids
  end

  def call(follow_up:, staff_id:)
    validate_outcome!
    refresh_source! if FINAL_OUTCOMES.include?(@outcome)
    clinic_id = follow_up.clinic_id
    ApplicationRecord.uncached do
      ApplicationRecord.transaction do
        Database.lock_clinic(clinic_id)
        staff = StaffMember.find_by(id: staff_id, clinic_id: clinic_id)
        current_case = FollowUpCase.for_clinic(clinic_id).find_by(id: follow_up.id)
        unless staff && current_case && Clinic.messaging_enabled.exists?(id: clinic_id)
          raise ReminderFlow::Conflict, "Open the appropriate workspace first."
        end

        now = Time.current
        ReconcileAppointments.new(now: now).for_case(current_case)
        # A returned conflict commits reconciliation. An exception rolls it back.
        record_action_on_reconciled_case(follow_up: current_case, staff: staff, now: now)
      end
    end
  end

  # Assessment replay supplies its own appointment state and observation time.
  def record_action_on_reconciled_case(follow_up:, staff:, now:)
    follow_up.with_lock do
      if follow_up.changed_for_staff?(staff, version: @version.to_i)
        next { error: "This case changed. Refresh it before acting." }
      end

      workflow = FollowUpWorkflow.new(now: now)
      if @outcome == "claim"
        record_claim(follow_up, staff, now: now)
        workflow.finish_cases(follow_up.clinic_id)
      else
        record_issue_outcome(follow_up, staff, now: now, workflow: workflow)
      end

      message = if @outcome == "attempted"
        "Contact attempt recorded. Follow-up stays open."
      else
        "Follow-up saved."
      end
      { message: message }
    end
  end

  private

  def validate_outcome!
    return if @outcome == "claim" || ISSUE_OUTCOMES.include?(@outcome) || %w[clarified unclear].include?(@outcome)

    raise ReminderFlow::Conflict, "Choose an action and record what happened."
  end

  def refresh_source!
    PmsSnapshot.new.refresh
  rescue ReminderFlow::Conflict
    raise ReminderFlow::Conflict, "Appointment data could not be refreshed. You can still claim work or record a contact attempt."
  end

  def record_claim(follow_up, staff, now:)
    ActivityEvent.record(
      actor: staff.name, kind: "claim", body: "Claimed responsibility for this follow-up.",
      at: now, case_id: follow_up.id
    )
    follow_up.mark_in_progress!(staff: staff, at: now)
  end

  def record_reply_clarification(issue, follow_up, staff, note, workflow, now)
    unless %w[clarified unclear].include?(@outcome)
      raise ReminderFlow::Conflict, "Clarify the reply before recording an appointment outcome."
    end
    ids = @appointment_ids
    unless ids.is_a?(Array) && ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }
      raise ReminderFlow::Conflict, "Choose the appointments this reply concerns."
    end
    candidates = Visit.for_clinic(follow_up.clinic_id).where(patient_id: follow_up.patient_id, id: issue.candidate_visit_ids)
    selected = candidates.where(appointment_id: ids.map(&:to_i)).to_a
    if @outcome == "clarified" && (selected.empty? || selected.map(&:appointment_id).sort != ids.map(&:to_i).uniq.sort)
      raise ReminderFlow::Conflict, "Choose from this reply's possible appointments."
    end
    selected = [] if @outcome == "unclear"
    description = selected.empty? ? "Reply still unclear." : "Reply applies to appointments #{selected.map(&:appointment_id).join(', ')}."
    event_id = ActivityEvent.record(actor: staff.name, kind: @outcome, body: "#{description} #{note}",
      at: now, case_id: follow_up.id, issue_id: issue.id, message_id: issue.reply_event.message_id)
    issue.update!(clarified_visit_ids: selected.map(&:id))
    if @outcome == "clarified"
      issue.update!(resolved_at: now, resolution_event_id: event_id)
      selected.each do |visit|
        next unless visit.current && visit.current_reply_target?(now: now)
        workflow.issue(visit, "patient", "Record the appointment outcome after clarifying the patient reply.", reopen: true)
      end
    end
    follow_up.reload.mark_in_progress!(staff: staff, at: now)
    workflow.finish_cases(follow_up.clinic_id)
  end

  def record_issue_outcome(follow_up, staff, now:, workflow:)
    unless follow_up.owner_id == staff.id
      raise ReminderFlow::Conflict, "Open the appropriate workspace first."
    end
    validate_outcome!
    note = @note.to_s.strip
    unless NOTE_LENGTH.cover?(note.length)
      raise ReminderFlow::Conflict, "Choose an action and record what happened."
    end

    issue = follow_up.issues.open.find_by(id: @issue_id.to_i)
    raise ReminderFlow::Conflict, "Choose an open issue." unless issue

    if issue.reply_event_id
      record_reply_clarification(issue, follow_up, staff, note, workflow, now)
      return
    end
    if %w[clarified unclear].include?(@outcome)
      raise ReminderFlow::Conflict, "Choose a reply review."
    end

    visit = Visit.current.for_clinic(follow_up.clinic_id).with_context.find_by(id: issue.visit_id)
    raise ReminderFlow::Conflict, "This appointment changed." unless visit

    if @outcome == "confirmed"
      visit.confirm!(actor: staff.name, at: now, agreement: true)
      workflow.close_after_confirmation(visit, actor: staff.name, event_kind: "confirmed")
      # Closing issues can advance this case's version.
      follow_up.reload
    end
    event_id = ActivityEvent.record(
      actor: staff.name, kind: @outcome, body: note,
      at: now, case_id: follow_up.id, visit_id: visit.id
    )
    if @outcome == "confirmed" &&
       !(issue.code == "contact" && workflow.preserve_contact_hold_on_confirmation?(visit))
      issue.update!(resolved_at: now, resolution_event_id: event_id)
    end
    follow_up.mark_in_progress!(staff: staff, at: now)

    if %w[rescheduled canceled].include?(@outcome)
      workflow.close_visit_follow_ups(visit, note, event_id: event_id)
    else
      workflow.finish_cases(follow_up.clinic_id)
    end
  end
end

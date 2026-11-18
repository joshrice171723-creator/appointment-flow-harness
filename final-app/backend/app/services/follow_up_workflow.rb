# Writes join the caller's app transaction; this class owns issue and case closure.
class FollowUpWorkflow
  def initialize(now:)
    @now = now
  end

  attr_reader :now

  # ReminderFlow holds the clinic lock for the entire batch.
  def with_locked_reminder_cases(clinic_id, patient_ids)
    @reminder_case_scope = FollowUpCase.for_clinic(clinic_id).where(patient_id: patient_ids)
    yield
  ensure
    @reminder_case_scope = @reminder_cases = nil
  end

  def finish_cases(clinic_id)
    open_case_ids = FollowUpIssue.open.select(:case_id)
    cases_without_open_issues = FollowUpCase.for_clinic(clinic_id)
      .where.not(state: "resolved").where.not(id: open_case_ids)

    cases_without_open_issues.each do |follow_up|
      follow_up.update!(state: "resolved", version: follow_up.version + 1, updated_at: now)
      remember_case(follow_up)
    end
  end

  def resolve_finished_follow_ups(clinic_id, case_id: nil)
    open_issues = FollowUpIssue.open
    open_issues = open_issues.where(case_id: case_id) if case_id
    open_visit_ids = open_issues.select(:visit_id)
    visits = Visit.for_clinic(clinic_id).where(id: open_visit_ids).includes(:appointment, :clinic_setting)

    visits.each do |visit|
      source = visit.appointment if visit.matches_appointment?(visit.appointment)
      starts_at_utc = visit.starts_at_utc
      obsolete = !visit.current || source&.status != "scheduled"
      next unless obsolete || (starts_at_utc && starts_at_utc <= now)

      reason = if source&.status == "complete"
        "The PMS marked this visit complete."
      elsif obsolete
        "The PMS changed or removed this appointment time."
      else
        "The appointment time passed. Follow-up was closed."
      end
      close_visit_follow_ups(visit, reason)
    end

    reviews = open_issues.for_clinic(clinic_id).where.not(reply_event_id: nil).includes(:visit).to_a
    candidates = Visit.for_clinic(clinic_id).where(id: reviews.flat_map(&:candidate_visit_ids))
      .includes(:appointment, :patient, :clinic_setting).index_by(&:id)
    reviews.each do |review|
      still_upcoming = review.candidate_visit_ids.any? do |id|
        visit = candidates[id]
        visit&.current && visit.current_reply_target?(now: now, source: visit.appointment)
      end
      next if still_upcoming

      close_issues([review], visit: review.visit, reason: "All possible appointments have passed or changed. Reply review was closed.")
    end
  end

  def close_visit_follow_ups(visit, reason, codes: nil, event_id: nil, actor: "Appointment Flow", kind: "follow_up_resolved")
    issues = FollowUpIssue.open.where(visit_id: visit.id, reply_event_id: nil)
    issues = issues.where(code: codes) if codes
    close_issues(issues.to_a, visit: visit, reason: reason, event_id: event_id, actor: actor, kind: kind)
  end

  private def close_issues(issues, visit:, reason:, event_id: nil, actor: "Appointment Flow", kind: "follow_up_resolved")
    issues_by_case = issues.group_by(&:case_id)
    return if issues_by_case.empty?

    issues_by_case.each do |case_id, closed_issues|
      resolution_event_id = event_id || ActivityEvent.record(
        actor: actor, kind: kind, body: reason, at: now, case_id: case_id, visit_id: visit.id
      )
      FollowUpIssue.where(id: closed_issues.map(&:id))
        .update_all(resolved_at: now, resolution_event_id: resolution_event_id)

      remaining_due = FollowUpIssue.open.where(case_id: case_id).minimum(:created_at)
      next unless remaining_due

      follow_up = FollowUpCase.find(case_id)
      follow_up.update!(due_at: remaining_due, version: follow_up.version + 1, updated_at: now)
      remember_case(follow_up)
    end
    finish_cases(visit.clinic_id)
  end

  def close_after_confirmation(visit, actor:, event_kind:)
    codes = %w[no_response delivery]
    codes << "contact" unless preserve_contact_hold_on_confirmation?(visit)
    close_visit_follow_ups(visit, "The appointment was confirmed.", codes: codes, actor: actor, kind: event_kind)
  end

  def preserve_contact_hold_on_confirmation?(visit)
    ContactPolicy.new(now).verification_conflict?(visit)
  end

  def issue(visit, code, reason, reopen: false, reason_code: nil, reply_event_id: nil, candidate_visit_ids: [], visit_issues: nil)
    # Sending and staff actions use the same lock to avoid duplicate cases.
    Database.lock_clinic(visit.clinic_id)
    existing_issue = if reply_event_id
      FollowUpIssue.find_by(reply_event_id: reply_event_id)
    elsif visit_issues
      visit_issues.find { |issue| issue.code == code && issue.reply_event_id.nil? }
    else
      FollowUpIssue.find_by(visit_id: visit.id, code: code, reply_event_id: nil)
    end
    if %w[contact no_response].include?(code) && existing_issue
      reopen = existing_issue.resolved_at.present? || existing_issue.reason != reason ||
        existing_issue.reason_code != reason_code&.to_s
    end
    return existing_issue.case_id if existing_issue && !reopen

    follow_up = case_for(visit)
    if follow_up
      reopening = follow_up.state == "resolved"
      follow_up.update!(
        state: "attention",
        owner_id: reopening ? nil : follow_up.owner_id,
        due_at: reopening ? now : [follow_up.due_at, now].min,
        updated_at: now,
        version: follow_up.version + 1
      )
    else
      follow_up = FollowUpCase.create!(
        patient_id: visit.patient_id, clinic_id: visit.clinic_id,
        state: "attention", due_at: now, updated_at: now
      )
    end
    remember_case(follow_up)

    if existing_issue
      previous_resolution = existing_issue.resolution_event_id
      transition = if existing_issue.resolved_at
        "issue_reopened"
      elsif existing_issue.reason != reason || existing_issue.reason_code != reason_code&.to_s
        "issue_reason_changed"
      end
      existing_issue.update!(resolved_at: nil, resolution_event_id: nil, reason: reason, reason_code: reason_code)
      record_issue_transition(existing_issue, transition, previous_resolution: previous_resolution) if transition
    else
      issue = FollowUpIssue.create!(
        case_id: follow_up.id, visit_id: visit.id, code: code, reason: reason, reason_code: reason_code, created_at: now,
        reply_event_id: reply_event_id, candidate_visit_ids: candidate_visit_ids
      )
      record_issue_transition(issue, "issue_opened")
    end
    follow_up.id
  end

  private

  def case_for(visit)
    if @reminder_case_scope
      @reminder_cases ||= @reminder_case_scope.index_by(&:patient_id)
      @reminder_cases[visit.patient_id]
    else
      FollowUpCase.find_by(patient_id: visit.patient_id, clinic_id: visit.clinic_id)
    end
  end

  def remember_case(follow_up)
    @reminder_cases[follow_up.patient_id] = follow_up if @reminder_cases
  end

  def record_issue_transition(issue, kind, previous_resolution: nil)
    ActivityEvent.record(actor: "Appointment Flow", kind: kind, body: issue.reason, at: now,
      case_id: issue.case_id, visit_id: issue.visit_id, issue_id: issue.id,
      previous_resolution_event_id: previous_resolution)
  end
end

require_relative "test_helper"

class FollowUpContactHistoryTest < Minitest::Test
  def setup
    restore_demo_fixture
  end

  def test_staff_confirmation_preserves_verification_hold_until_clear
    visit = Visit.current.find_by!(appointment_id: 104)
    staff = StaffMember.find(11)
    verification = PatientDetailVerification.create!(
      patient_id: visit.patient_id, staff: staff, field: "wireless_phone",
      verified_value: "+17375582104", verified_at: TEST_NOW, conflicted_at: TEST_NOW
    )
    ReminderFlow.new(now: TEST_NOW).run(1)
    issue = visit.issues.open.find_by!(code: "contact")
    assert_equal "conflicting_details", issue.reason_code
    follow_up = issue.follow_up_case
    follow_up.mark_in_progress!(staff: staff, at: TEST_NOW)

    result = RecordFollowUp.new(outcome: "confirmed", version: follow_up.version,
      issue_id: issue.id, note: "The patient confirmed the appointment.")
      .record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: TEST_NOW)

    assert_equal "Follow-up saved.", result.fetch(:message)
    assert visit.reload.confirmed_at
    assert_nil issue.reload.resolved_at
    ReminderFlow.new(now: TEST_NOW).run(1)
    assert_nil issue.reload.resolved_at
    assert_empty visit.messages

    verification.update!(conflicted_at: nil)
    ReminderFlow.new(now: TEST_NOW).run(1)
    assert issue.reload.resolved_at
    assert visit.reload.confirmed_at
  end

  def test_reopening_keeps_one_issue_and_links_the_previous_resolution
    visit = Visit.current.find_by!(appointment_id: 104)
    workflow = FollowUpWorkflow.new(now: TEST_NOW)
    case_id = workflow.issue(visit, "contact", "No phone number on file and no usable email.", reason_code: :missing_phone)
    issue = FollowUpIssue.open.find_by!(case_id: case_id, visit_id: visit.id, code: "contact")
    workflow.close_visit_follow_ups(visit, "Contact was available.", codes: ["contact"])
    previous_resolution = issue.reload.resolution_event_id

    workflow.issue(visit, "contact", "Invalid phone number on file and no usable email.", reason_code: :invalid_phone)
    assert_equal 1, FollowUpIssue.where(visit_id: visit.id, code: "contact").count
    assert_nil issue.reload.resolved_at
    assert_equal "invalid_phone", issue.reason_code
    event = ActivityEvent.find_by!(issue_id: issue.id, kind: "issue_reopened")
    assert_equal previous_resolution, event.previous_resolution_event_id
    assert_equal issue.reason, event.body
  end
end

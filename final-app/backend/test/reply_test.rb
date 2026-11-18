require_relative "test_helper"

class ReplyTest < Minitest::Test
  CLINIC_ID = 994
  PATIENT_ID = 994
  APPOINTMENT_ID = 994001
  PHONE = "(512) 555-0194"
  APPOINTMENT_AT = Time.utc(2026, 11, 12, 12)

  def with_reply_fixture
    Database.open do |db|
      db.transaction do
        Clinic.insert_all!([{ id: CLINIC_ID, name: "Reply fixture" }])
        ClinicSetting.create!(clinic_id: CLINIC_ID, timezone: "America/Chicago", sender: "+15125550194")
        add_patient(id: PATIENT_ID, phone: PHONE)
        add_appointment(id: APPOINTMENT_ID, patient_id: PATIENT_ID, at: APPOINTMENT_AT)
        SourceSync.upsert_all([{ id: 1, last_synced_at: Arel.sql("clock_timestamp()") }])
        DemoState.where(id: 1).update_all(fail_next: false)
        flow = ReminderFlow.new
        ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)
        visit = flow.load_visits(CLINIC_ID).sole
        receipt = send_sms(flow, visit)

        yield flow, visit, receipt
        raise ActiveRecord::Rollback
      end
    end
  end

  def add_patient(id:, phone:)
    row = {
      id: id, first_name: "Reply", last_name: "Patient", birthdate: Date.new(1990, 1, 1),
      wireless_phone: phone, email: "reply-#{id}@example.test", preferred_language: "en"
    }
    Patient.insert_all!([row.merge(ContactComparison.patient_values(row.stringify_keys))])
    ContactPermission.create!(patient_id: id, clinic_id: CLINIC_ID, sms: true, email: true)
  end

  def add_appointment(id:, patient_id:, at:)
    Appointment.insert_all!([{
      id: id, patient_id: patient_id, clinic_id: CLINIC_ID, start_at: at, status: "scheduled"
    }])
  end

  def send_sms(flow, visit, purpose: "initial")
    flow.reminder_sender.deliver(
      visit: visit, channel: "SMS", destination: flow.contact_policy.phone(visit.patient.wireless_phone),
      purposes: [purpose], recipient_id: visit.patient_id
    )
    Message.where(clinic_id: CLINIC_ID).order(:id).last
  end

  def test_standalone_affirmative_confirms_the_only_matching_visit
    with_reply_fixture do |flow, visit, receipt|
      assert_equal "Appointment confirmed.", ReceiveReply.new(now: flow.now).reply(
        visit: visit, text: "Yeah!", receipt: receipt, request_key: "unique-yes"
      )
      assert visit.reload.confirmed_at
      assert_empty FollowUpIssue.open.where(visit_id: visit.id)
    end
  end

  def test_retry_after_a_lost_response_keeps_one_reply_and_case_transition
    with_reply_fixture do |flow, visit, receipt|
      replies = ReceiveReply.new(now: flow.now)
      body = "No, I can't make it."
      key = "lost-response"
      expected = replies.reply_to_receipt(receipt: receipt, text: body, request_key: key)
      issue = FollowUpIssue.open.where(visit_id: visit.id).sole
      version = issue.follow_up_case.version

      assert_equal "Reply sent to Needs attention.", expected
      assert_equal expected, replies.reply_to_receipt(receipt: receipt, text: body, request_key: key)
      assert_equal version, issue.follow_up_case.reload.version
      assert_equal [body], ActivityEvent.where(message_id: receipt.id, actor: "Patient").pluck(:body)

      assert_raises(ReminderFlow::Conflict) do
        replies.reply_to_receipt(receipt: receipt, text: "YES", request_key: key)
      end
      another_receipt = send_sms(flow, visit, purpose: "courtesy")
      assert_raises(ReminderFlow::Conflict) do
        replies.reply_to_receipt(receipt: another_receipt, text: body, request_key: key)
      end
      assert_equal 1, ActivityEvent.where(request_key: key).count
    end
  end

  def test_reply_classification_keeps_uncertain_text_for_review
    assert_equal :decline, ReplyClassification.call("NO")
    assert_equal :decline, ReplyClassification.call("No, I can't make it")
    assert_equal :affirmative, ReplyClassification.call("YES")
    assert_equal :review, ReplyClassification.call("YES, please call me")
    assert_equal :review, ReplyClassification.call("No problem, I'll be there.")
  end

  def test_yes_with_a_request_creates_staff_review_without_confirming
    with_reply_fixture do |flow, visit, receipt|
      assert_equal "Reply sent to Needs attention.", ReceiveReply.new(now: flow.now).reply(
        visit: visit, text: "Yes, but call me.", receipt: receipt, request_key: "yes-with-request"
      )
      refute visit.reload.confirmed_at
      issue = FollowUpIssue.open.where(visit_id: visit.id).sole
      assert_equal "patient", issue.code
      assert_equal "Yes, but call me.", ActivityEvent.where(visit_id: visit.id, kind: "reply").sole.body
    end
  end

  def test_two_patients_sharing_a_number_require_matching_review
    with_reply_fixture do |flow, visit, receipt|
      other_patient_id = PATIENT_ID + 1
      add_patient(id: other_patient_id, phone: PHONE)
      add_appointment(id: APPOINTMENT_ID + 1, patient_id: other_patient_id, at: APPOINTMENT_AT + 1.hour)
      ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)

      assert_equal "Reply sent to Needs attention.", ReceiveReply.new(now: flow.now).reply(
        visit: visit, text: "YES", receipt: receipt, request_key: "shared-number"
      )
      refute visit.reload.confirmed_at
      assert_equal "ambiguous_reply", FollowUpIssue.open.where(visit_id: visit.id).sole.code
    end
  end

  def test_two_sent_visits_in_one_sms_conversation_require_matching_review
    with_reply_fixture do |flow, first_visit, first_receipt|
      add_appointment(id: APPOINTMENT_ID + 1, patient_id: PATIENT_ID, at: APPOINTMENT_AT + 1.day)
      ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)
      second_visit = flow.load_visits(CLINIC_ID).find { |visit| visit.appointment_id == APPOINTMENT_ID + 1 }
      second_receipt = send_sms(flow, second_visit)

      assert_equal "Reply sent to Needs attention.", ReceiveReply.new(now: flow.now).reply(
        visit: first_visit, text: "NO", receipt: first_receipt, request_key: "two-visits-no"
      )
      [first_visit, second_visit].each do |visit|
        refute visit.reload.confirmed_at
      end
      review = FollowUpIssue.for_clinic(CLINIC_ID).open.where(code: "ambiguous_reply").sole
      assert_equal [first_visit.id, second_visit.id].sort, review.candidate_visit_ids.sort
      assert_equal "NO", review.reply_event.body

      travel_to(TEST_NOW.change(hour: 18))
      assert_equal "Reply sent to Needs attention.", ReceiveReply.new(now: flow.now).reply(
        visit: second_visit, text: "YES", receipt: second_receipt, request_key: "two-visits-yes"
      )
      refute second_visit.reload.confirmed_at
      event = ActivityEvent.find_by!(request_key: "two-visits-yes")
      assert_equal "ambiguous_reply", event.kind
      assert_nil event.visit_id
    end
  end

  def test_staff_can_clarify_one_both_or_neither_without_changing_the_pms
    [[APPOINTMENT_ID], [APPOINTMENT_ID, APPOINTMENT_ID + 1], []].each do |selected_ids|
      with_reply_fixture do |flow, first_visit, receipt|
        add_appointment(id: APPOINTMENT_ID + 1, patient_id: PATIENT_ID, at: APPOINTMENT_AT + 1.hour)
        ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)
        second_visit = Visit.current.find_by!(appointment_id: APPOINTMENT_ID + 1)
        send_sms(flow, second_visit)
        ReceiveReply.new(now: flow.now).reply(visit: first_visit, text: "test test", receipt: receipt,
          request_key: "clarification-#{selected_ids.join('-')}")
        review = FollowUpIssue.for_clinic(CLINIC_ID).open.where(code: "ambiguous_reply").sole
        assert_equal "test test", review.reply_event.body
        follow_up = review.follow_up_case
        staff = StaffMember.create!(clinic_id: CLINIC_ID, name: "Reply reviewer")
        RecordFollowUp.new(outcome: "claim", version: follow_up.version).call(follow_up: follow_up, staff_id: staff.id)
        before = Appointment.for_clinic(CLINIC_ID).order(:id).map(&:attributes)
        outcome = selected_ids.empty? ? "unclear" : "clarified"
        RecordFollowUp.new(outcome: outcome, version: follow_up.reload.version,
          issue_id: review.id, appointment_ids: selected_ids, note: "Called to clarify the reply.")
          .call(follow_up: follow_up, staff_id: staff.id)
        review.reload
        assert_equal selected_ids.sort, Visit.where(id: review.clarified_visit_ids).pluck(:appointment_id).sort
        assert_equal selected_ids.any?, review.resolved_at.present?
        assert_equal 1, FollowUpIssue.where(reply_event_id: review.reply_event_id).count
        assert_equal selected_ids.sort, FollowUpIssue.for_clinic(CLINIC_ID).open
          .where(code: "patient", reply_event_id: nil).joins(:visit).pluck("desk.visits.appointment_id").sort
        assert_equal before, Appointment.for_clinic(CLINIC_ID).order(:id).map(&:attributes)
        assert_nil first_visit.reload.confirmed_at
        assert_nil second_visit.reload.confirmed_at
      end
    end
  end

  def test_reply_review_closes_only_after_all_candidate_appointments_finish
    with_reply_fixture do |flow, first_visit, receipt|
      add_appointment(id: APPOINTMENT_ID + 1, patient_id: PATIENT_ID, at: APPOINTMENT_AT + 1.day)
      ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)
      second_visit = Visit.current.find_by!(appointment_id: APPOINTMENT_ID + 1)
      send_sms(flow, second_visit)
      ReceiveReply.new(now: flow.now).reply(visit: first_visit, text: "test test", receipt: receipt,
        request_key: "finished-candidates")
      review = FollowUpIssue.for_clinic(CLINIC_ID).open.where(code: "ambiguous_reply").sole

      Appointment.where(id: first_visit.appointment_id).update_all(status: "complete")
      ReconcileAppointments.new(now: flow.now).for_clinic(CLINIC_ID)
      assert_nil review.reload.resolved_at
      refute_equal "resolved", review.follow_up_case.reload.state

      finished_at = second_visit.starts_at_utc + 1.minute
      ReconcileAppointments.new(now: finished_at).for_clinic(CLINIC_ID)
      assert_equal finished_at, review.reload.resolved_at
      assert_equal "resolved", review.follow_up_case.reload.state
      assert_equal "follow_up_resolved", review.resolution_event.kind
      assert_empty review.clarified_visit_ids
      assert_equal "test test", review.reply_event.body
      ReconcileAppointments.new(now: finished_at).for_clinic(CLINIC_ID)
      assert_equal 1, ActivityEvent.where(case_id: review.case_id, kind: "follow_up_resolved").count
    end
  end
end

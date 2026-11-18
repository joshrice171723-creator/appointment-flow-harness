require_relative "test_helper"

class ConcurrentDeliveryTest < Minitest::Test
  FIXTURE_ID = 8_100_001

  def test_concurrent_runs_do_not_duplicate_delivery
    fresh_at = SourceSync.find(1).last_synced_at
    fixture_created = false
    ApplicationRecord.transaction do
      Clinic.insert_all!([{ id: FIXTURE_ID, name: "Concurrent delivery test clinic" }])
      Patient.insert_all!([{ id: FIXTURE_ID, first_name: "Demo Patient", last_name: FIXTURE_ID.to_s,
        birthdate: Date.new(1990, 1, 1), wireless_phone: "+15125550101", preferred_language: "en" }])
      ClinicSetting.create!(clinic_id: FIXTURE_ID, timezone: "America/Chicago", sender: "+15125550102")
      ContactPermission.create!(clinic_id: FIXTURE_ID, patient_id: FIXTURE_ID, sms: true)
      local_date = TEST_NOW.in_time_zone("America/Chicago").to_date + ReminderSchedule::INITIAL_DAYS_BEFORE
      Appointment.insert_all!([{ id: FIXTURE_ID, clinic_id: FIXTURE_ID, patient_id: FIXTURE_ID,
        start_at: Time.utc(local_date.year, local_date.month, local_date.day, 12), status: "scheduled" }])
      SourceSync.where(id: 1).update_all(last_synced_at: Arel.sql("clock_timestamp()"))
    end
    fixture_created = true

    results = 2.times.map do
      Thread.new { Rails.application.executor.wrap { ReminderFlow.new(now: TEST_NOW).run(FIXTURE_ID) } }
    end.map(&:value).sort
    assert_equal [0, 1], results
    assert_equal 1, Message.where(clinic_id: FIXTURE_ID, patient_id: FIXTURE_ID).count
  ensure
    if fixture_created
      ApplicationRecord.transaction do
        cases = FollowUpCase.for_clinic(FIXTURE_ID)
        visits = Visit.for_clinic(FIXTURE_ID)
        messages = Message.where(clinic_id: FIXTURE_ID)
        IssueCandidate.where(issue_id: FollowUpIssue.where(case_id: cases.select(:id)).select(:id)).delete_all
        AppointmentHistory.where(clinic_id: FIXTURE_ID).delete_all
        FollowUpIssue.where(case_id: cases.select(:id)).delete_all
        ActivityEvent.where(visit_id: visits.select(:id))
          .or(ActivityEvent.where(case_id: cases.select(:id)))
          .or(ActivityEvent.where(message_id: messages.select(:id))).delete_all
        MessageItem.where(message_id: messages.select(:id)).delete_all
        messages.delete_all
        cases.delete_all
        visits.delete_all
        ContactPermission.where(clinic_id: FIXTURE_ID).delete_all
        ClinicSetting.where(clinic_id: FIXTURE_ID).delete_all
        Appointment.where(id: FIXTURE_ID).delete_all
        Patient.where(id: FIXTURE_ID).delete_all
        Clinic.where(id: FIXTURE_ID).delete_all
        SourceSync.where(id: 1).update_all(last_synced_at: fresh_at)
      end
    end
  end
end

class RecordFollowUpIssueHistory < ActiveRecord::Migration[8.1]
  LEGACY_CONTACT_REASONS = {
    "Patient mapping needs review." => "patient_mapping",
    "Appointment time needs review." => "appointment_time",
    "Verify the patient's age and authorized contact." => "missing_age",
    "Review conflicting PMS and locally verified patient details before sending reminders." => "conflicting_details",
    "Verify an authorized adult before contacting this patient." => "authorized_adult",
    "No valid phone or email on file." => "no_contact",
    "Arrange a conversation in the patient's preferred language." => "language",
    "No phone number on file and no usable email." => "missing_phone",
    "Invalid phone number on file and no usable email." => "invalid_phone",
    "No permitted SMS or email channel. Check permissions and opt-outs." => "permission",
    "The recipient opted out of SMS and has no permitted email channel." => "opt_out"
  }.freeze

  def up
    add_column "desk.issues", :reason_code, :text
    add_column "desk.events", :issue_id, :bigint
    add_column "desk.events", :previous_resolution_event_id, :bigint

    LEGACY_CONTACT_REASONS.each do |reason, code|
      execute <<~SQL
        UPDATE desk.issues SET reason_code = #{connection.quote(code)}
        WHERE code = 'contact' AND reason = #{connection.quote(reason)}
      SQL
    end
  end

  def down
    remove_column "desk.events", :previous_resolution_event_id
    remove_column "desk.events", :issue_id
    remove_column "desk.issues", :reason_code
  end
end

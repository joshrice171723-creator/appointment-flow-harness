class SupportActiveRecordQueries < ActiveRecord::Migration[8.1]
  def up
    # These are app-owned mirror columns. The external PMS remains unchanged.
    add_column "pms.patients", :comparison_phone, :text
    add_column "pms.patients", :comparison_email, :text
    add_column "pms.patients", :phone_quality, :text
    add_index "pms.patients", :comparison_phone
    add_index "pms.patients", :comparison_email
    add_column "desk.patient_detail_verifications", :comparison_value, :text
    add_index "desk.patient_detail_verifications", [:field, :comparison_value],
      where: "retired_at IS NULL", name: :detail_contact_comparison

    # Stored values remain correct for bulk writes as well as individual saves.
    add_column "pms.appointments", :start_month, :virtual, type: :date,
      as: "date_trunc('month', start_at)::date", stored: true
    add_column "desk.visits", :start_month, :virtual, type: :date,
      as: "date_trunc('month', start_at)::date", stored: true
    add_column "pms.patients", :missing_birthdate, :virtual, type: :boolean,
      as: "birthdate IS NULL", stored: true
    add_column "desk.issues", :resolved, :virtual, type: :boolean,
      as: "resolved_at IS NOT NULL", stored: true

    create_table "desk.issue_candidates", primary_key: [:issue_id, :visit_id] do |t|
      t.bigint :issue_id, null: false
      t.bigint :visit_id, null: false
    end
    add_foreign_key "desk.issue_candidates", "desk.issues", column: :issue_id
    add_foreign_key "desk.issue_candidates", "desk.visits", column: :visit_id
    add_index "desk.issue_candidates", [:visit_id, :issue_id]
    add_index "pms.appointments", [:patient_id, :clinic_id, :start_at, :id], name: :patient_appointment_history
    add_index "desk.visits", [:patient_id, :clinic_id, :start_at, :appointment_id], name: :patient_visit_history
    add_index "pms.appointments", [:patient_id, :clinic_id]
    add_index "desk.people", [:clinic_id, :authorized_guarantor_id]
    create_table "desk.appointment_histories", primary_key: [:appointment_id, :patient_id, :clinic_id] do |t|
      t.bigint :appointment_id, null: false
      t.bigint :patient_id, null: false
      t.bigint :clinic_id, null: false
      t.datetime :start_at, null: false, precision: nil
    end
    add_foreign_key "desk.appointment_histories", "pms.clinics", column: :clinic_id
    add_index "desk.appointment_histories", [:patient_id, :clinic_id, :start_at, :appointment_id], name: :tracked_appointment_history

    [Patient, Appointment, Visit, FollowUpIssue, PatientDetailVerification].each(&:reset_column_information)
    Patient.find_each do |patient|
      Patient.where(id: patient.id).update_all(ContactComparison.patient_values(patient.attributes))
    end
    PatientDetailVerification.find_each do |detail|
      detail.update_columns(comparison_value: detail.contact_comparison)
    end
    FollowUpIssue.find_each(&:sync_candidates)
    # Backfill through the same owner as ordinary single and bulk visit creation.
    Visit.find_in_batches { |visits| AppointmentHistory.record_visits(visits) }
  end

  def down
    drop_table "desk.issue_candidates"
    drop_table "desk.appointment_histories"
    remove_index "pms.appointments", name: :patient_appointment_history
    remove_index "desk.visits", name: :patient_visit_history
    remove_index "pms.appointments", [:patient_id, :clinic_id]
    remove_index "desk.people", [:clinic_id, :authorized_guarantor_id]
    remove_column "desk.issues", :resolved
    remove_column "pms.patients", :missing_birthdate
    remove_column "desk.visits", :start_month
    remove_column "pms.appointments", :start_month
    remove_column "desk.patient_detail_verifications", :comparison_value
    remove_column "pms.patients", :comparison_phone
    remove_column "pms.patients", :comparison_email
    remove_column "pms.patients", :phone_quality
  end
end

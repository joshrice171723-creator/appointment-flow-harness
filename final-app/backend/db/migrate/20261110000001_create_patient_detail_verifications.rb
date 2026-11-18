class CreatePatientDetailVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table "desk.patient_detail_verifications" do |t|
      t.bigint :patient_id, null: false
      t.bigint :staff_id, null: false
      t.text :field, null: false
      t.text :pms_value
      t.text :verified_value, null: false
      t.timestamptz :verified_at, null: false
      t.timestamptz :aligned_at
      t.timestamptz :conflicted_at
      t.timestamptz :retired_at
    end
    add_foreign_key "desk.patient_detail_verifications", "pms.patients", column: :patient_id
    add_foreign_key "desk.patient_detail_verifications", "desk.staff", column: :staff_id
    add_index "desk.patient_detail_verifications", [:patient_id, :field], unique: true,
      where: "retired_at IS NULL", name: "active_patient_detail_verification"
  end
end

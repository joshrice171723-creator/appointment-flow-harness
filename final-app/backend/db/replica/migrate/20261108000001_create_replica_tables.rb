class CreateReplicaTables < ActiveRecord::Migration[8.1]
  def change
    create_schema :pms

    create_table "pms.clinics" do |t|
      t.text :name, null: false
      t.text :address_line
      t.text :city
      t.column :state, "char(2)"
      t.text :phone
    end
    create_table "pms.patients" do |t|
      t.text :first_name, null: false
      t.text :last_name, null: false
      t.date :birthdate
      t.text :wireless_phone
      t.text :email
      t.text :preferred_language
      t.bigint :guarantor_id
    end
    add_foreign_key "pms.patients", "pms.patients", column: :guarantor_id
    create_table "pms.appointments" do |t|
      t.bigint :patient_id, null: false
      t.bigint :clinic_id, null: false
      t.text :provider_name
      t.datetime :start_at, precision: nil, null: false
      t.integer :length_minutes
      t.text :procedure_note
      t.text :status, null: false
      t.datetime :updated_at, precision: nil
    end
    add_foreign_key "pms.appointments", "pms.patients", column: :patient_id
    add_foreign_key "pms.appointments", "pms.clinics", column: :clinic_id
    add_index "pms.appointments", [:clinic_id, :start_at], name: :appointment_window

  end
end

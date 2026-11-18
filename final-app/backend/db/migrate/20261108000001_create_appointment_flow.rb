class CreateAppointmentFlow < ActiveRecord::Migration[8.1]
  def change
    create_schema :pms
    create_schema :desk

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

    create_table "desk.clinic_settings", primary_key: :clinic_id do |t|
      t.text :timezone, null: false
      t.text :sender, null: false
      t.date :last_reminder_on
    end
    add_foreign_key "desk.clinic_settings", "pms.clinics", column: :clinic_id
    add_index "desk.clinic_settings", :sender, unique: true
    create_table "desk.reporting_clinic_zones", primary_key: :clinic_id do |t|
      t.text :timezone, null: false
    end
    add_foreign_key "desk.reporting_clinic_zones", "pms.clinics", column: :clinic_id
    create_table "desk.people", primary_key: [:patient_id, :clinic_id] do |t|
      t.bigint :patient_id, null: false
      t.bigint :clinic_id, null: false
      t.boolean :sms, default: false, null: false
      t.boolean :email, default: false, null: false
      t.bigint :authorized_guarantor_id
    end
    add_foreign_key "desk.people", "pms.patients", column: :patient_id
    add_foreign_key "desk.people", "pms.clinics", column: :clinic_id
    add_foreign_key "desk.people", "pms.patients", column: :authorized_guarantor_id
    create_table "desk.staff" do |t|
      t.bigint :clinic_id, null: false
      t.text :name, null: false
    end
    add_foreign_key "desk.staff", "pms.clinics", column: :clinic_id
    create_table "desk.demo" do |t|
      t.timestamptz :seeded_at, null: false
      t.boolean :fail_next, default: false, null: false
      t.text :dataset, null: false
    end
    add_check_constraint "desk.demo", "id = 1"
    create_table "desk.source_sync" do |t|
      t.timestamptz :last_synced_at, null: false
    end
    add_check_constraint "desk.source_sync", "id = 1"
    create_table "desk.visits" do |t|
      t.bigint :appointment_id, null: false
      t.bigint :patient_id, null: false
      t.bigint :clinic_id, null: false
      t.text :revision, null: false
      t.datetime :start_at, precision: nil, null: false
      t.boolean :current, default: true, null: false
      t.timestamptz :confirmed_at
      t.text :confirmed_by
      t.timestamptz :agreed_at
    end
    add_foreign_key "desk.visits", "pms.clinics", column: :clinic_id
    add_index "desk.visits", :appointment_id, unique: true, where: "current", name: :visit_current
    add_index "desk.visits", [:clinic_id, :start_at], name: :visit_clinic
    create_table "desk.cases" do |t|
      t.bigint :patient_id, null: false
      t.bigint :clinic_id, null: false
      t.text :state, null: false
      t.bigint :owner_id
      t.timestamptz :due_at, null: false
      t.integer :version, default: 1, null: false
      t.timestamptz :updated_at, null: false
    end
    add_foreign_key "desk.cases", "pms.clinics", column: :clinic_id
    add_foreign_key "desk.cases", "desk.staff", column: :owner_id
    add_index "desk.cases", [:patient_id, :clinic_id], unique: true
    add_check_constraint "desk.cases", "state IN ('attention','progress','resolved')"
    create_table "desk.issues" do |t|
      t.bigint :case_id, null: false
      t.bigint :visit_id, null: false
      t.text :code, null: false
      t.text :reason, null: false
      t.timestamptz :created_at, null: false
      t.timestamptz :resolved_at
      t.bigint :resolution_event_id
    end
    add_foreign_key "desk.issues", "desk.cases", column: :case_id
    add_foreign_key "desk.issues", "desk.visits", column: :visit_id
    add_index "desk.issues", [:visit_id, :code], unique: true
    add_index "desk.issues", :case_id, where: "resolved_at IS NULL", name: :issue_open
    create_table "desk.messages" do |t|
      t.bigint :patient_id, null: false
      t.bigint :clinic_id, null: false
      t.text :clinic_name, null: false
      t.text :sender, null: false
      t.text :channel, null: false
      t.text :destination, null: false
      t.text :body, null: false
      t.text :token, null: false
      t.timestamptz :created_at, null: false
      t.text :status, null: false
      t.text :receipt
      t.bigint :recipient_id
    end
    add_foreign_key "desk.messages", "pms.patients", column: :recipient_id
    add_index "desk.messages", :token, unique: true
    add_index "desk.messages", [:clinic_id, :created_at], name: :message_clinic
    add_check_constraint "desk.messages", "channel IN ('SMS','Email')"
    add_check_constraint "desk.messages", "status IN ('sent','failed')"
    create_table "desk.message_items", primary_key: [:visit_id, :purpose] do |t|
      t.bigint :message_id, null: false
      t.bigint :visit_id, null: false
      t.text :purpose, null: false
    end
    add_foreign_key "desk.message_items", "desk.messages", column: :message_id
    add_foreign_key "desk.message_items", "desk.visits", column: :visit_id
    add_check_constraint "desk.message_items", "purpose IN ('initial','backup','follow_up','courtesy')"
    create_table "desk.events" do |t|
      t.bigint :case_id
      t.bigint :visit_id
      t.bigint :message_id
      t.timestamptz :created_at, null: false
      t.text :actor, null: false
      t.text :kind, null: false
      t.text :body, null: false
      t.text :request_key
    end
    add_foreign_key "desk.events", "desk.cases", column: :case_id
    add_foreign_key "desk.events", "desk.visits", column: :visit_id
    add_foreign_key "desk.events", "desk.messages", column: :message_id
    add_foreign_key "desk.issues", "desk.events", column: :resolution_event_id
    add_index "desk.events", :request_key, unique: true
    add_index "desk.events", [:case_id, :id], name: :event_case
    add_index "desk.events", :visit_id, where: "kind IN ('rescheduled','canceled')", name: :event_pms_change
    create_table "desk.opt_outs", primary_key: [:clinic_id, :destination] do |t|
      t.bigint :clinic_id, null: false
      t.text :destination, null: false
    end
    add_foreign_key "desk.opt_outs", "pms.clinics", column: :clinic_id
  end
end

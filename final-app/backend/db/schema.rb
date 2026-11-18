# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_17_000004) do
  create_schema "desk"
  create_schema "pms"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "pms.appointments", force: :cascade do |t|
    t.bigint "clinic_id", null: false
    t.integer "length_minutes"
    t.bigint "patient_id", null: false
    t.text "procedure_note"
    t.text "provider_name"
    t.datetime "start_at", precision: nil, null: false
    t.virtual "start_month", type: :date, as: "(date_trunc('month'::text, start_at))::date", stored: true
    t.text "status", null: false
    t.datetime "updated_at", precision: nil
    t.index ["clinic_id", "start_at"], name: "appointment_window"
    t.index ["patient_id", "clinic_id", "start_at", "id"], name: "patient_appointment_history"
    t.index ["patient_id", "clinic_id"], name: "index_appointments_on_patient_id_and_clinic_id"
  end

  create_table "pms.clinics", force: :cascade do |t|
    t.text "address_line"
    t.text "city"
    t.text "name", null: false
    t.text "phone"
    t.string "state", limit: 2
  end

  create_table "pms.patients", force: :cascade do |t|
    t.date "birthdate"
    t.text "comparison_email"
    t.text "comparison_phone"
    t.text "email"
    t.text "first_name", null: false
    t.bigint "guarantor_id"
    t.text "last_name", null: false
    t.virtual "missing_birthdate", type: :boolean, as: "(birthdate IS NULL)", stored: true
    t.text "phone_quality"
    t.text "preferred_language"
    t.text "wireless_phone"
    t.index ["comparison_email"], name: "index_patients_on_comparison_email"
    t.index ["comparison_phone"], name: "index_patients_on_comparison_phone"
  end

  add_foreign_key "pms.appointments", "pms.clinics"
  add_foreign_key "pms.appointments", "pms.patients"
  add_foreign_key "pms.patients", "pms.patients", column: "guarantor_id"

  create_table "desk.appointment_histories", primary_key: ["appointment_id", "patient_id", "clinic_id"], force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.bigint "clinic_id", null: false
    t.bigint "patient_id", null: false
    t.datetime "start_at", precision: nil, null: false
    t.index ["patient_id", "clinic_id", "start_at", "appointment_id"], name: "tracked_appointment_history"
  end

  create_table "desk.cases", force: :cascade do |t|
    t.bigint "clinic_id", null: false
    t.timestamptz "due_at", null: false
    t.bigint "owner_id"
    t.bigint "patient_id", null: false
    t.text "state", null: false
    t.timestamptz "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["patient_id", "clinic_id"], name: "index_cases_on_patient_id_and_clinic_id", unique: true
    t.check_constraint "state = ANY (ARRAY['attention'::text, 'progress'::text, 'resolved'::text])"
  end

  create_table "desk.clinic_settings", primary_key: "clinic_id", force: :cascade do |t|
    t.date "last_reminder_on"
    t.text "sender", null: false
    t.text "timezone", null: false
    t.index ["sender"], name: "index_clinic_settings_on_sender", unique: true
  end

  create_table "desk.demo", force: :cascade do |t|
    t.text "dataset", null: false
    t.boolean "fail_next", default: false, null: false
    t.timestamptz "seeded_at", null: false
    t.check_constraint "id = 1"
  end

  create_table "desk.events", force: :cascade do |t|
    t.text "actor", null: false
    t.text "body", null: false
    t.bigint "case_id"
    t.timestamptz "created_at", null: false
    t.bigint "issue_id"
    t.text "kind", null: false
    t.bigint "message_id"
    t.bigint "previous_resolution_event_id"
    t.text "request_key"
    t.bigint "visit_id"
    t.index ["case_id", "id"], name: "event_case"
    t.index ["request_key"], name: "index_events_on_request_key", unique: true
    t.index ["visit_id"], name: "event_pms_change", where: "(kind = ANY (ARRAY['rescheduled'::text, 'canceled'::text]))"
    t.index ["visit_id"], name: "index_events_on_visit_id"
  end

  create_table "desk.issue_candidates", primary_key: ["issue_id", "visit_id"], force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.bigint "visit_id", null: false
    t.index ["visit_id", "issue_id"], name: "index_issue_candidates_on_visit_id_and_issue_id"
  end

  create_table "desk.issues", force: :cascade do |t|
    t.jsonb "candidate_visit_ids", default: [], null: false
    t.bigint "case_id", null: false
    t.jsonb "clarified_visit_ids", default: [], null: false
    t.text "code", null: false
    t.timestamptz "created_at", null: false
    t.text "reason", null: false
    t.text "reason_code"
    t.bigint "reply_event_id"
    t.bigint "resolution_event_id"
    t.virtual "resolved", type: :boolean, as: "(resolved_at IS NOT NULL)", stored: true
    t.timestamptz "resolved_at"
    t.bigint "visit_id", null: false
    t.index ["case_id"], name: "issue_open", where: "(resolved_at IS NULL)"
    t.index ["reply_event_id"], name: "index_issues_on_reply_event_id", unique: true
    t.index ["visit_id", "code"], name: "visit_issue_without_reply", unique: true, where: "(reply_event_id IS NULL)"
    t.index ["visit_id"], name: "open_issue_visits", where: "(resolved_at IS NULL)"
  end

  create_table "desk.message_items", primary_key: ["visit_id", "purpose"], force: :cascade do |t|
    t.bigint "message_id", null: false
    t.text "purpose", null: false
    t.bigint "visit_id", null: false
    t.index ["message_id"], name: "index_message_items_on_message_id"
    t.check_constraint "purpose = ANY (ARRAY['initial'::text, 'backup'::text, 'follow_up'::text, 'courtesy'::text])"
  end

  create_table "desk.messages", force: :cascade do |t|
    t.text "body", null: false
    t.text "channel", null: false
    t.bigint "clinic_id", null: false
    t.text "clinic_name", null: false
    t.timestamptz "created_at", null: false
    t.text "destination", null: false
    t.bigint "patient_id", null: false
    t.text "receipt"
    t.bigint "recipient_id"
    t.text "sender", null: false
    t.text "status", null: false
    t.text "token", null: false
    t.index ["clinic_id", "channel", "sender", "destination"], name: "sent_conversation", where: "(status = 'sent'::text)"
    t.index ["clinic_id", "created_at"], name: "message_clinic"
    t.index ["token"], name: "index_messages_on_token", unique: true
    t.check_constraint "channel = ANY (ARRAY['SMS'::text, 'Email'::text])"
    t.check_constraint "status = ANY (ARRAY['sent'::text, 'failed'::text])"
  end

  create_table "desk.opt_outs", primary_key: ["clinic_id", "destination"], force: :cascade do |t|
    t.bigint "clinic_id", null: false
    t.text "destination", null: false
  end

  create_table "desk.patient_detail_verifications", force: :cascade do |t|
    t.timestamptz "aligned_at"
    t.text "comparison_value"
    t.timestamptz "conflicted_at"
    t.text "field", null: false
    t.bigint "patient_id", null: false
    t.text "pms_value"
    t.timestamptz "retired_at"
    t.bigint "staff_id", null: false
    t.timestamptz "verified_at", null: false
    t.text "verified_value", null: false
    t.index ["field", "comparison_value"], name: "detail_contact_comparison", where: "(retired_at IS NULL)"
    t.index ["patient_id", "field"], name: "active_patient_detail_verification", unique: true, where: "(retired_at IS NULL)"
  end

  create_table "desk.people", primary_key: ["patient_id", "clinic_id"], force: :cascade do |t|
    t.bigint "authorized_guarantor_id"
    t.bigint "clinic_id", null: false
    t.boolean "email", default: false, null: false
    t.bigint "patient_id", null: false
    t.boolean "sms", default: false, null: false
    t.index ["clinic_id", "authorized_guarantor_id"], name: "index_people_on_clinic_id_and_authorized_guarantor_id"
  end

  create_table "desk.reporting_clinic_zones", primary_key: "clinic_id", force: :cascade do |t|
    t.text "timezone", null: false
  end

  create_table "desk.source_sync", force: :cascade do |t|
    t.timestamptz "last_synced_at", null: false
    t.string "snapshot_digest"
    t.check_constraint "id = 1"
  end

  create_table "desk.staff", force: :cascade do |t|
    t.bigint "clinic_id", null: false
    t.text "name", null: false
  end

  create_table "desk.visits", force: :cascade do |t|
    t.timestamptz "agreed_at"
    t.bigint "appointment_id", null: false
    t.bigint "clinic_id", null: false
    t.timestamptz "confirmed_at"
    t.text "confirmed_by"
    t.boolean "current", default: true, null: false
    t.bigint "patient_id", null: false
    t.text "revision", null: false
    t.datetime "start_at", precision: nil, null: false
    t.virtual "start_month", type: :date, as: "(date_trunc('month'::text, start_at))::date", stored: true
    t.index ["appointment_id"], name: "visit_appointment"
    t.index ["appointment_id"], name: "visit_current", unique: true, where: "current"
    t.index ["clinic_id", "start_at"], name: "visit_clinic"
    t.index ["patient_id", "clinic_id", "start_at", "appointment_id"], name: "patient_visit_history"
  end

  add_foreign_key "desk.appointment_histories", "pms.clinics"
  add_foreign_key "desk.cases", "desk.staff", column: "owner_id"
  add_foreign_key "desk.cases", "pms.clinics"
  add_foreign_key "desk.clinic_settings", "pms.clinics"
  add_foreign_key "desk.events", "desk.cases"
  add_foreign_key "desk.events", "desk.messages"
  add_foreign_key "desk.events", "desk.visits"
  add_foreign_key "desk.issue_candidates", "desk.issues"
  add_foreign_key "desk.issue_candidates", "desk.visits"
  add_foreign_key "desk.issues", "desk.cases"
  add_foreign_key "desk.issues", "desk.events", column: "reply_event_id"
  add_foreign_key "desk.issues", "desk.events", column: "resolution_event_id"
  add_foreign_key "desk.issues", "desk.visits"
  add_foreign_key "desk.message_items", "desk.messages"
  add_foreign_key "desk.message_items", "desk.visits"
  add_foreign_key "desk.messages", "pms.patients", column: "recipient_id"
  add_foreign_key "desk.opt_outs", "pms.clinics"
  add_foreign_key "desk.patient_detail_verifications", "desk.staff"
  add_foreign_key "desk.patient_detail_verifications", "pms.patients"
  add_foreign_key "desk.people", "pms.clinics"
  add_foreign_key "desk.people", "pms.patients"
  add_foreign_key "desk.people", "pms.patients", column: "authorized_guarantor_id"
  add_foreign_key "desk.reporting_clinic_zones", "pms.clinics"
  add_foreign_key "desk.staff", "pms.clinics"
  add_foreign_key "desk.visits", "pms.clinics"
end

require_relative "../db/replica/seeds"

url = ENV.fetch("PMS_ADMIN_URL", "postgresql://desk@127.0.0.1:55439/apex_pms_contact_demo")
admin = URI(url)
name = admin.path.delete_prefix("/")
admin.path = "/postgres"
Database.provision(admin.to_s) do |db|
  unless db.exec_params("SELECT 1 FROM pg_database WHERE datname=$1", [name]).ntuples.positive?
    db.exec("CREATE DATABASE #{db.quote_ident(name)}")
  end
end

# Only setup has this writable connection. Runtime uses PmsReplica's SELECT-only login.
ReplicaSeed::Record.establish_connection(url)
paths = [Rails.root.join("db/replica/migrate").to_s]
ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(ReplicaSeed::Record.connection_db_config) do
  ActiveRecord::MigrationContext.new(paths).migrate
end
now = ENV["SEED_AT"] ? Time.iso8601(ENV.fetch("SEED_AT")) : Time.current
if ReplicaSeed::Clinic.exists?
  ReplicaSeed.normalize_legacy_patient_names
else
  ReplicaSeed.load(now: now)
end
ReplicaSeed.seed_phoenix_comparison_month(now: now)

if ENV["ASSESSMENT_REMINDERS_START"].present?
  launch = Date.iso8601(ENV.fetch("ASSESSMENT_REMINDERS_START"))
  ReplicaSeed.backfill_history(first_day: launch.prev_month.beginning_of_month)
  if ENV["CLINIC_SETUP_FILE"].present?
    require_relative "../db/assessment_task_examples"
    setup = JSON.parse(File.read(ENV.fetch("CLINIC_SETUP_FILE")))
    AssessmentTaskExamples.seed_replica(now: now, clinics: setup.fetch("messaging_clinics", []), launch: launch)
    require_relative "../db/assessment_patient_details"
    AssessmentPatientDetails.seed_replica(now: now, clinics: setup.fetch("messaging_clinics", []))
  end
end

reader = URI(ENV.fetch("PMS_READER_URL", "postgresql://pms_reader@127.0.0.1:55439/apex_pms_contact_demo"))
role = URI.decode_www_form_component(reader.user)
Database.provision(url) do |db|
  unless db.exec_params("SELECT 1 FROM pg_roles WHERE rolname=$1", [role]).ntuples.positive?
    password = reader.password ? " PASSWORD #{db.escape_literal(URI.decode_www_form_component(reader.password))}" : ""
    db.exec("CREATE ROLE #{db.quote_ident(role)} LOGIN#{password}")
  end
  db.exec("GRANT USAGE ON SCHEMA pms TO #{db.quote_ident(role)}")
  db.exec("GRANT SELECT ON ALL TABLES IN SCHEMA pms TO #{db.quote_ident(role)}")
end

# Run through the Compose scale profile. Only these disposable databases are replaced.
require "bundler/setup"
require "uri"
require "benchmark"
%w[DENTAL_DATABASE_URL PMS_READER_URL APP_ADMIN_URL].each { |key| ENV.fetch(key) }
app = URI(ENV.fetch("DENTAL_DATABASE_URL"))
prefix = ENV.fetch("SCALE_DATABASE_PREFIX", "apex_scale")
abort "Use letters, digits, and underscores for SCALE_DATABASE_PREFIX." unless prefix.match?(/\A[a-z][a-z0-9_]*\z/)
app.path = "/#{prefix}_test"
source = URI(ENV.fetch("APP_ADMIN_URL"))
source.path = "/#{prefix}_source_test"
reader = URI(ENV.fetch("PMS_READER_URL"))
reader.path = source.path
ENV.update("DENTAL_DATABASE_URL" => app.to_s, "PMS_ADMIN_URL" => source.to_s,
           "PMS_READER_URL" => reader.to_s, "SEED_AT" => "2026-11-05T10:00:00-06:00")
require_relative "../config/environment"
require "active_support/testing/time_helpers"
include ActiveSupport::Testing::TimeHelpers
load File.expand_path("setup.rb", __dir__)

PG.connect(source.to_s) do |db|
  db.exec(<<~SQL)
    TRUNCATE pms.appointments,pms.patients,pms.clinics CASCADE;
    INSERT INTO pms.clinics(id,name,state)
    SELECT id,'Scale clinic '||id,'TX' FROM generate_series(1,60) id;
    INSERT INTO pms.patients(id,first_name,last_name,birthdate,wireless_phone,email,preferred_language)
    SELECT id,'Demo Patient',id::text,'1980-01-01','+1512'||(2000000+id),
      'patient'||id||'@example.test',CASE WHEN id%5=0 THEN 'es' ELSE 'en' END
    FROM generate_series(1,56000) id;
    WITH days AS (
      SELECT day,row_number() OVER (ORDER BY day)-1 AS day_index
      FROM (SELECT day FROM generate_series('2026-11-12'::date,'2026-12-05'::date,interval '1 day') day
        WHERE extract(isodow FROM day)<7 ORDER BY day LIMIT 14) open_days
    )
    INSERT INTO pms.appointments(id,patient_id,clinic_id,start_at,length_minutes,status,updated_at)
    SELECT day_index*4000+slot,day_index*4000+slot,1+(slot-1)%60,
      day+interval '12 hours',30,'scheduled','2026-11-05 09:55'
    FROM days CROSS JOIN generate_series(1,4000) slot;
    ANALYZE pms.clinics;
    ANALYZE pms.patients;
    ANALYZE pms.appointments;
  SQL
end

def measure_changed_import(db)
  snapshot_locked = Queue.new
  lock_statement = "SELECT pg_advisory_xact_lock(#{Database::SNAPSHOT_LOCK_KEY})"
  observe_lock = lambda do |*notification|
    snapshot_locked << true if notification.last[:sql] == lock_statement
  end
  importer = Thread.new do
    ActiveSupport::Notifications.subscribed(observe_lock, "sql.active_record") do
      Benchmark.realtime { PmsSnapshot.new.refresh }
    end
  rescue StandardError => error
    snapshot_locked << error
    raise
  end
  signal = snapshot_locked.pop(timeout: 60)
  raise signal if signal.is_a?(Exception)
  raise "Snapshot lock was not acquired" unless signal

  clinic_lock_seconds = Benchmark.realtime { db.transaction { Database.lock_clinic(1) } }
  [importer.value, clinic_lock_seconds]
end

Database.open do |db|
  db.exec("DROP SCHEMA desk CASCADE; DROP SCHEMA pms CASCADE")
  ActiveRecord::Base.connection_pool.schema_migration.delete_all_versions
  ActiveRecord::Base.connection_pool.migration_context.migrate
  travel_to(Time.iso8601(ENV.fetch("SEED_AT")))
  import_seconds = Benchmark.realtime { PmsSnapshot.new.refresh }
  unchanged_import_seconds = Benchmark.realtime { PmsSnapshot.new.refresh }
  snapshot_payload_bytes = JSON.generate(PmsReplica.read).bytesize
  PG.connect(source.to_s) do |source_db|
    source_db.exec("UPDATE pms.appointments SET provider_name='Scale provider' WHERE id=56000")
  end
  changed_import_seconds, concurrent_clinic_lock_seconds = measure_changed_import(db)
  db.exec(<<~SQL)
    INSERT INTO desk.clinic_settings(clinic_id,timezone,sender)
    SELECT id,'America/Chicago','+1512555'||lpad(id::text,4,'0') FROM pms.clinics;
    INSERT INTO desk.people(patient_id,clinic_id,sms,email)
    SELECT patient_id,clinic_id,true,true FROM pms.appointments;
    INSERT INTO desk.demo(id,seeded_at,dataset) VALUES(1,now(),'isolated-scale');
    ANALYZE pms.clinics;
    ANALYZE pms.patients;
    ANALYZE pms.appointments;
    ANALYZE desk.people;
    ANALYZE desk.clinic_settings;
  SQL
  sent = 0
  batch_seconds = Benchmark.realtime do
    ReminderFlow.new.due_batches.each do |clinic, day|
      sent += ReminderFlow.new.run_daily_batch(clinic, day)
    end
  end
  repeated = 0
  repeat_seconds = Benchmark.realtime do
    (1..60).each do |clinic|
      repeated += ReminderFlow.new.run_daily_batch(clinic, Date.new(2026,11,5))
    end
  end
  counts = db.first_row("SELECT (SELECT count(*) FROM pms.clinics) clinics,(SELECT count(*) FROM pms.appointments) appointments,(SELECT count(*) FROM desk.messages) messages")
  raise "Scale fixture or duplicate protection failed: #{counts}" unless counts.values_at("clinics","appointments","messages") == [60,56000,4000] && sent == 4000 && repeated.zero?
  report_seconds = Benchmark.realtime { OperationsQuery.call }
  selected_report_seconds = Benchmark.realtime { OperationsQuery.call(month: "current") }
  calendar_seconds = Benchmark.realtime { AppointmentsQuery.new(Clinic.find(1), date: Date.new(2026, 11, 12)).call }
  puts JSON.pretty_generate(counts.merge(appointments_per_day: 4000, days: 14,
    snapshot_payload_bytes: snapshot_payload_bytes, full_replica_import_seconds: import_seconds.round(3),
    unchanged_replica_import_seconds: unchanged_import_seconds.round(3),
    changed_replica_import_seconds: changed_import_seconds.round(3),
    concurrent_clinic_lock_seconds: concurrent_clinic_lock_seconds.round(3),
    batch_seconds: batch_seconds.round(3), reporting_seconds: report_seconds.round(3),
    selected_month_reporting_seconds: selected_report_seconds.round(3), calendar_seconds: calendar_seconds.round(3),
    repeated_batch_seconds: repeat_seconds.round(3), duplicate_sends: repeated,
    delivery: "Fake sender; includes database work, excludes real provider/network latency"))
end

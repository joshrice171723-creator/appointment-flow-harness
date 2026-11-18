require_relative "test_helper"

class ReplicaTest < Minitest::Test



  def setup
    restore_demo_fixture
    @url = ENV.fetch("PMS_READER_URL")
    abort "Use a disposable PMS database ending in _test." unless URI(@url).path.end_with?("_test")
  end

  def test_supplied_schema_and_read_only_role
    expected = {
      "clinics" => ["id:bigint:NO", "name:text:NO", "address_line:text:YES", "city:text:YES", "state:character:YES", "phone:text:YES"],
      "patients" => ["id:bigint:NO", "first_name:text:NO", "last_name:text:NO", "birthdate:date:YES", "wireless_phone:text:YES", "email:text:YES", "preferred_language:text:YES", "guarantor_id:bigint:YES"],
      "appointments" => ["id:bigint:NO", "patient_id:bigint:NO", "clinic_id:bigint:NO", "provider_name:text:YES", "start_at:timestamp without time zone:NO", "length_minutes:integer:YES", "procedure_note:text:YES", "status:text:NO", "updated_at:timestamp without time zone:YES"]
    }
    PG.connect(@url) do |db|
      expected.each do |table, columns|
        actual = db.exec_params(<<~SQL, [table]).map { |row| row.values.join(":") }
          SELECT column_name,data_type,is_nullable FROM information_schema.columns
          WHERE table_schema='pms' AND table_name=$1 ORDER BY ordinal_position
        SQL
        assert_equal columns, actual
        assert_raises(PG::InsufficientPrivilege) { db.exec("UPDATE pms.#{table} SET id=id WHERE false") }
      end
      assert_equal "2", db.exec("SELECT character_maximum_length FROM information_schema.columns WHERE table_schema='pms' AND table_name='clinics' AND column_name='state'").first.values.first
      constraints = db.exec(<<~SQL).map { |row| row.values.join(":") }
        SELECT c.relname,k.contype FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='pms'
        AND k.contype IN ('p','f') ORDER BY c.relname,k.contype
      SQL
      assert_equal %w[appointments:f appointments:f appointments:p clinics:p patients:f patients:p], constraints
    end
  end

  def test_snapshot_reads_only_supplied_tables_and_preserves_source
    PG.connect(@url) do |db|
      checksum_sql = "SELECT md5(string_agg(row_to_json(a)::text,',' ORDER BY id)) AS checksum FROM pms.appointments a"
      before = db.exec(checksum_sql).first.fetch("checksum")
      initial = PmsReplica.read
      assert_equal %w[appointments clinics patients], initial.keys.sort
      Time.use_zone("America/Chicago") { assert_equal initial, PmsReplica.read }
      travel_to(Time.current + 60.days)
      assert_equal initial, PmsReplica.read
      assert_nil db.exec("SELECT to_regclass('pms_demo.outcomes')").first.values.first
      after = db.exec(checksum_sql).first.fetch("checksum")
      assert_equal before, after
    end
  end

  def test_refresh_keeps_demo_history_and_tracks_older_appointments_by_id
    recent, old, tracked, moved, missing = (992401..992405).to_a
    PG.connect(ENV.fetch("PMS_ADMIN_URL")) do |source|
      source.exec_params(<<~SQL, [recent, old, tracked, moved])
        INSERT INTO pms.appointments (id, patient_id, clinic_id, start_at, status)
        SELECT sample.id, appointment.patient_id, appointment.clinic_id, sample.start_at, 'complete'
        FROM (SELECT patient_id, clinic_id FROM pms.appointments ORDER BY id LIMIT 1) appointment
        CROSS JOIN (VALUES ($1::bigint, '2026-10-01'::timestamp), ($2, '2024-10-01'),
                           ($3, '2024-10-01'), ($4, '2024-10-01')) sample(id, start_at)
      SQL
      patient_id, clinic_id = source.exec_params(
        "SELECT patient_id, clinic_id FROM pms.appointments WHERE id = $1", [tracked]
      ).first.values_at("patient_id", "clinic_id")
      Appointment.insert_all!([old, tracked, moved, missing].map do |id|
        { id: id, patient_id: patient_id, clinic_id: clinic_id, status: "scheduled",
          start_at: id == old || id == tracked ? Time.utc(2024, 10, 1) : Time.utc(2026, 10, 1) }
      end)
      Visit.insert_all!([{ appointment_id: tracked, patient_id: patient_id, clinic_id: clinic_id,
                          revision: "tracked", start_at: Time.utc(2024, 10, 1) }])

      PmsSnapshot.new.refresh

      assert_equal "complete", Appointment.find(recent).status
      assert_equal "scheduled", Appointment.find(old).status
      assert_equal "complete", Appointment.find(tracked).status
      assert_equal Time.utc(2024, 10, 1), Appointment.find(moved).start_at
      assert_equal "complete", Appointment.find(moved).status
      assert_equal "missing", Appointment.find(missing).status
    ensure
      source.exec_params("DELETE FROM pms.appointments WHERE id = ANY($1::bigint[])", ["{#{[recent, old, tracked, moved].join(',')}}"])
    end
  end

  def test_empty_appointment_snapshot_preserves_cached_appointments_and_freshness
    appointment = Appointment.scheduled.where(start_at: TEST_NOW..).first!
    last_sync = SourceSync.find(1).last_synced_at
    snapshot = PmsReplica.read.merge("appointments" => [])

    with_replica(snapshot) do
      error = assert_raises(ReminderFlow::Conflict) { PmsSnapshot.new.refresh }
      assert_match(/returned no appointments/, error.message)
    end

    assert_equal "scheduled", appointment.reload.status
    assert_equal last_sync, SourceSync.find(1).last_synced_at
  end

  def test_unavailable_source_keeps_the_original_sanitized_failure_and_cause
    unavailable = URI(@url)
    unavailable.path += "_missing_test"
    ENV["PMS_READER_URL"] = unavailable.to_s
    error = assert_raises(ReminderFlow::Conflict) { PmsReplica.read }
    assert_equal "PMS snapshot unavailable: PG::ConnectionBad.", error.message
    assert_kind_of ActiveRecord::ActiveRecordError, error.cause
    assert_instance_of PG::ConnectionBad, error.cause.cause
  ensure
    ENV["PMS_READER_URL"] = @url
  end
end

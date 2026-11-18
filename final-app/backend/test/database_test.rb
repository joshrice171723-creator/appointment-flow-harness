require_relative "test_helper"

class DatabaseTest < Minitest::Test
  def test_sql_result_conversion_preserves_rails_timestamp_decoding
    original_timezone = ENV["TZ"]
    ENV["TZ"] = "EST5"
    Database.open do |db|
      db.transaction do
        appointment = Appointment.find(102)
        source_time = db.exec_params(
          "SELECT to_char(start_at, 'YYYY-MM-DD HH24:MI:SS') AS wall_time FROM pms.appointments WHERE id=$1",
          [appointment.id]
        ).first.fetch("wall_time")
        visit = Visit.create!(
          appointment_id: appointment.id, patient_id: appointment.patient_id,
          clinic_id: appointment.clinic_id, revision: "timestamp-regression",
          start_at: appointment.start_at, current: false
        )

        assert_equal source_time, visit.reload.start_at.strftime("%F %T")
        assert visit.matches_appointment?(appointment)
        assert_equal 7, db.exec("SELECT 7::bigint AS count").first.fetch("count")
        raise ActiveRecord::Rollback
      end
    end
  ensure
    ENV["TZ"] = original_timezone
  end

  def test_repeated_opens_reuse_catalog_types_without_changing_rails_decoder
    ApplicationRecord.connection_pool.with_connection do |connection|
      raw = connection.raw_connection
      rails_decoder = raw.type_map_for_results
      reads = count_catalog_reads(raw) do
        3.times do
          Database.open do |db|
            assert_equal({ "number" => 7, "enabled" => true, "payload" => { "ok" => true } },
              db.exec(%q(SELECT 7::bigint AS number, true AS enabled, '{"ok":true}'::json AS payload)).first)
          end
        end
      end
      assert_operator reads, :<=, 1, "Repeated opens should not reload the PostgreSQL type catalog"
      assert_same rails_decoder, raw.type_map_for_results
    end
  end

  def test_new_connection_loads_its_own_catalog_types
    PG.connect(ENV.fetch("DENTAL_DATABASE_URL")) do |raw|
      adapter = Struct.new(:raw_connection).new(raw)
      reads = count_catalog_reads(raw) do
        2.times do
          db = Database::Session.new(adapter)
          assert_equal 7, db.exec("SELECT 7::bigint AS number").first.fetch("number")
        end
      end
      assert_equal 1, reads, "A new connection must load its own catalog once"
    end
  end

  def test_reconnected_connection_reloads_catalog_types
    PG.connect(ENV.fetch("DENTAL_DATABASE_URL")) do |raw|
      adapter = Struct.new(:raw_connection).new(raw)
      Database::Session.new(adapter)
      previous_backend = raw.backend_pid
      raw.reset
      refute_equal previous_backend, raw.backend_pid
      reads = count_catalog_reads(raw) do
        db = Database::Session.new(adapter)
        assert_equal 7, db.exec("SELECT 7::bigint AS number").first.fetch("number")
      end
      assert_equal 1, reads, "Reconnecting must invalidate the cached catalog"
    end
  end
  private

  def count_catalog_reads(raw)
    reads = 0
    original = raw.method(:exec)
    raw.define_singleton_method(:exec) do |sql, *args, **kwargs, &block|
      reads += 1 if sql.match?(/FROM pg_type\b/)
      original.call(sql, *args, **kwargs, &block)
    end
    yield
    reads
  ensure
    raw.singleton_class.remove_method(:exec)
  end
end

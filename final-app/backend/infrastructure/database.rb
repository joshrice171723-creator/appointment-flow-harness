require "pg"

module Database
  APP_URL = "postgresql://flow_app@127.0.0.1:55439/apex_flow_contact_demo"
  # Separate advisory-lock namespaces prevent unrelated workflows sharing a lock.
  SNAPSHOT_LOCK_KEY = 824020
  CLINIC_LOCK_NAMESPACE = 824021
  APPOINTMENT_LOCK_NAMESPACE = 824022
  # PostgreSQL's two-key lock takes signed int32 keys. Collisions only serialize extra work.
  LOCK_KEY_MODULUS = 2_147_483_647
  REQUEST_HASH_SEED = 0

  # Bulk population can otherwise leave the first requests planning against empty-table statistics.
  def self.analyze_table(table_name)
    connection = ApplicationRecord.connection
    connection.execute("ANALYZE #{connection.quote_table_name(table_name)}")
  end

  # Raw SQL fixtures and benchmarks borrow Rails' app connection.
  def self.open
    ApplicationRecord.connection_pool.with_connection do |connection|
      ApplicationRecord.uncached { yield Session.new(connection) }
    end
  end

  # Setup connects with its own credential; application models never use it.
  def self.provision(url, &block)
    PG.connect(url, &block)
  end

  # Imports and setup take the exclusive snapshot lock; clinic work shares it, then locks its clinic.
  # Call inside the same transaction as the clinic's writes.
  def self.lock_clinic(clinic_id)
    connection = ApplicationRecord.connection
    key = Integer(clinic_id) % LOCK_KEY_MODULUS
    connection.execute("SELECT pg_advisory_xact_lock_shared(#{SNAPSHOT_LOCK_KEY})")
    connection.execute("SELECT pg_advisory_xact_lock(#{CLINIC_LOCK_NAMESPACE},#{key})")
  end

  def self.lock_snapshot
    ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{SNAPSHOT_LOCK_KEY})")
  end

  def self.lock_appointment(appointment_id)
    key = Integer(appointment_id) % LOCK_KEY_MODULUS
    ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{APPOINTMENT_LOCK_NAMESPACE},#{key})")
  end

  # Acquire the same appointment locks in a stable order, with one database round trip.
  def self.lock_appointments(appointment_ids)
    keys = appointment_ids.map { |id| Integer(id) % LOCK_KEY_MODULUS }.uniq.sort
    return if keys.empty?

    ApplicationRecord.connection.execute(<<~SQL)
      SELECT pg_advisory_xact_lock(#{APPOINTMENT_LOCK_NAMESPACE}, key)
      FROM (SELECT unnest(ARRAY[#{keys.join(',')}]) AS key ORDER BY key) ordered_keys
    SQL
  end

  def self.lock_request(request_key)
    connection = ApplicationRecord.connection
    key = connection.quote(request_key)
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{key},#{REQUEST_HASH_SEED}))")
  end

  # Bulk SQL and models must share a connection so locks and rollback cover both.
  class Session
    def initialize(connection)
      @connection = connection
      @raw = connection.raw_connection
      # The PG constructor reads the type catalog; reuse it for this pooled connection.
      cached_types = @raw.instance_variable_get(:@appointment_flow_result_types)
      if cached_types && cached_types.first == @raw.backend_pid
        @result_types = cached_types.last
      else
        @result_types = PG::BasicTypeMapForResults.new(@raw)
        @raw.instance_variable_set(:@appointment_flow_result_types, [@raw.backend_pid, @result_types])
      end
    end

    delegate :quote_ident, :escape_literal, to: :@raw

    # Decode SQL results without replacing Rails' UTC timestamp decoder.
    def exec(sql)
      @raw.exec(sql).map_types!(@result_types)
    end

    def exec_params(sql, parameters)
      @raw.exec_params(sql, parameters).map_types!(@result_types)
    end

    def rows(sql, *args)
      exec_params(sql, args).to_a
    end

    def first_row(sql, *args)
      rows(sql, *args).first
    end

    def transaction
      @connection.transaction do
        @connection.materialize_transactions
        yield self
      end
    end
  end
end

# Load inside a Rails test and wrap the synchronous caller under measurement.
require "active_support/notifications"

module RailsWorkloadProbe
  READ_STATEMENT = /\A\s*SELECT\b/i
  WRITE_STATEMENT = /\A\s*(?:INSERT|UPDATE|DELETE|MERGE|TRUNCATE)\b/i

  def self.measure
    owner = Thread.current
    metrics = {
      database_statements: 0,
      cached_statements: 0,
      direct_write_statements: 0,
      instantiated_records: 0,
      schema_statements: 0,
      read_statements: 0,
      read_rows: 0,
      largest_read_rows: 0,
      reads_without_row_count: 0,
      affected_rows: 0,
      write_result_rows: 0,
      writes_without_result_row_count: 0,
      writes_without_affected_rows: 0
    }
    sql = lambda do |event|
      next unless Thread.current.equal?(owner)

      payload = event.payload
      if payload[:name] == "SCHEMA"
        metrics[:schema_statements] += 1
        next
      end

      if payload[:cached]
        metrics[:cached_statements] += 1
      else
        metrics[:database_statements] += 1
        statement = payload[:sql].to_s
        if WRITE_STATEMENT.match?(statement)
          metrics[:direct_write_statements] += 1
          result_rows = payload[:row_count]
          if result_rows.is_a?(Integer)
            metrics[:write_result_rows] += result_rows
          else
            metrics[:writes_without_result_row_count] += 1
          end
          affected_rows = payload[:affected_rows]
          if affected_rows.is_a?(Integer)
            metrics[:affected_rows] += affected_rows
          else
            metrics[:writes_without_affected_rows] += 1
          end
        elsif READ_STATEMENT.match?(statement)
          metrics[:read_statements] += 1
          row_count = payload[:row_count]
          if row_count.is_a?(Integer)
            metrics[:read_rows] += row_count
            metrics[:largest_read_rows] = [metrics[:largest_read_rows], row_count].max
          else
            metrics[:reads_without_row_count] += 1
          end
        end
      end
    end
    instantiation = lambda do |event|
      if Thread.current.equal?(owner)
        metrics[:instantiated_records] += event.payload.fetch(:record_count)
      end
    end

    result = ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
      ActiveSupport::Notifications.subscribed(instantiation, "instantiation.active_record") do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        value = yield
        metrics[:elapsed_ms] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1_000
        value
      end
    end
    [result, metrics.freeze]
  end
end

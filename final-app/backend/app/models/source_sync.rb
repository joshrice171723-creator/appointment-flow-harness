class SourceSync < ApplicationRecord
  self.table_name = "desk.source_sync"
  MAX_CACHE_AGE = 5.minutes

  # Cache age uses real time, even when a workflow uses a simulated visit date.
  def self.wall_clock
    Time.at(Process.clock_gettime(Process::CLOCK_REALTIME)).utc
  end

  def self.status
    uncached do
      synced_at = find_by(id: 1)&.last_synced_at
      stale = synced_at.nil? || synced_at < wall_clock - MAX_CACHE_AGE
      # Response contract: Time or nil, boolean, and a warning string or nil.
      {
        "last_synced_at" => synced_at,
        "stale" => stale,
        "message" => stale ? "Appointment data is stale. Check the PMS before acting." : nil
      }
    end
  end
end

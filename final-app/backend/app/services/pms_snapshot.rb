require "digest"

class PmsSnapshot
  APPOINTMENT_IMPORT_BATCH_SIZE = 2_000
  STATISTICS_REFRESH_ROWS = 100
  # Bump this when the mirror's source-field conversions change.
  MIRROR_FORMAT = 1
  COLUMNS = PmsReplica::COLUMNS

  CACHE_MODELS = { "clinics" => Clinic, "patients" => Patient, "appointments" => Appointment }.freeze

  def initialize(read_snapshot: nil)
    @read_snapshot = read_snapshot
  end

  def refresh(observed_at: nil, &configure_clinics)
    ApplicationRecord.transaction do
      Database.lock_snapshot
      import_snapshot(observed_at: observed_at || Time.current, &configure_clinics)
    end
  end

  def refresh_if_stale
    return unless SourceSync.status["stale"]

    ApplicationRecord.transaction do
      Database.lock_snapshot
      import_snapshot(observed_at: Time.current) if SourceSync.status["stale"]
    end
  end

  private

  # The cache rows and freshness timestamp commit or roll back together.
  def import_snapshot(observed_at:)
    if @read_snapshot
      snapshot = @read_snapshot.call
    else
      since = appointment_history_start(observed_at)
      watched_ids = watched_appointment_ids(since)
      snapshot = PmsReplica.read(appointments_since: since, appointment_ids: watched_ids)
    end
    validate_snapshot!(snapshot)
    if watched_ids.present? && snapshot.fetch("appointments").empty?
      raise ReminderFlow::Conflict, "PMS returned no appointments while the app is tracking appointments."
    end
    digest = snapshot_digest(snapshot)
    upsert_source_records(snapshot) unless SourceSync.where(id: 1).pick(:snapshot_digest) == digest
    reconcile_patient_details(snapshot.fetch("patients"), at: observed_at)
    yield snapshot if block_given?
    grant_default_demo_permissions
    mark_missing_scheduled_appointments(snapshot.fetch("appointments"), watched_ids: watched_ids)
    record_sync_time(digest)
  rescue KeyError => error
    raise ReminderFlow::Conflict, "PMS snapshot unavailable: #{error.class}."
  end

  def appointment_history_start(observed_at)
    previous_month = observed_at.to_date.prev_month.beginning_of_month
    launch = ENV["ASSESSMENT_REMINDERS_START"].presence
    return previous_month unless launch

    [previous_month, Date.iso8601(launch).prev_month.beginning_of_month].min
  end

  def watched_appointment_ids(since)
    open_visit_ids = FollowUpIssue.open.flat_map { |issue| [issue.visit_id, *issue.affected_visit_ids] }
    tracked = Visit.current.or(Visit.where(id: open_visit_ids)).distinct.pluck(:appointment_id)
    # An appointment that moves before the cutoff must still be read by ID.
    tracked | Appointment.scheduled.where(start_at: since..).pluck(:id)
  end

  def reconcile_patient_details(patients, at:)
    patient_ids = patients.to_set { |row| row.fetch("id") }
    PatientDetailVerification.active.includes(:patient).find_each do |verification|
      verification.reconcile_source!(at: at) if patient_ids.include?(verification.patient_id)
    end
  end

  def validate_snapshot!(snapshot)
    raise ReminderFlow::Conflict, "Invalid PMS snapshot." unless snapshot.is_a?(Hash)

    COLUMNS.each_key do |table|
      records = snapshot.fetch(table)
      unless records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) }
        raise ReminderFlow::Conflict, "Invalid PMS snapshot."
      end
    end
  end

  def upsert_source_records(snapshot)
    COLUMNS.each do |table, columns|
      model = CACHE_MODELS.fetch(table)
      records = snapshot.fetch(table)
      batches = table == "appointments" ? records.each_slice(APPOINTMENT_IMPORT_BATCH_SIZE) : [records]
      changed_count = batches.sum { |batch| import_changed_records(model, columns, batch) }
      Database.analyze_table(model.table_name) if changed_count >= STATISTICS_REFRESH_ROWS
    end
  end

  def import_changed_records(model, columns, records)
    rows = records.map do |record|
      columns.to_h { |column| [column, model.type_for_attribute(column).cast(record[column])] }
    end
    rows.each { |row| row.merge!(ContactComparison.patient_values(row)) } if model == Patient
    return 0 if rows.empty?

    compared_columns = rows.first.keys
    existing = model.where(id: rows.map { |row| row.fetch("id") }).pluck(*compared_columns)
      .to_h { |values| [values.first, values] }
    changed = rows.reject { |row| existing[row.fetch("id")] == row.values }
    model.upsert_all(changed, unique_by: :id, returning: false, record_timestamps: false) if changed.any?
    changed.length
  end

  def grant_default_demo_permissions
    pairs = Appointment.where(clinic_id: ClinicSetting.select(:clinic_id))
      .left_joins(:contact_permission).where(:"desk.people" => { patient_id: nil })
      .distinct.pluck(:patient_id, :clinic_id)
    permissions = pairs.map do |patient_id, clinic_id|
      { patient_id: patient_id, clinic_id: clinic_id, sms: true, email: true }
    end

    # Existing permissions, including revocations, take precedence.
    ContactPermission.insert_all(permissions, returning: false) if permissions.any?
    Database.analyze_table(ContactPermission.table_name) if permissions.length >= STATISTICS_REFRESH_ROWS
  end

  def mark_missing_scheduled_appointments(appointments, watched_ids:)
    # A missing appointment leaves outreach without counting as a scheduling outcome.
    source_ids = appointments.map { |appointment| appointment.fetch("id") }
    missing = if watched_ids
      missing_ids = watched_ids - source_ids
      return if missing_ids.empty?
      Appointment.scheduled.where(id: missing_ids)
    else
      Appointment.scheduled.where.not(id: source_ids)
    end
    missing.update_all(status: "missing")
  end

  def snapshot_digest(snapshot)
    source_records = COLUMNS.keys.map { |table| snapshot.fetch(table) }
    Digest::SHA256.hexdigest(JSON.generate([MIRROR_FORMAT, source_records]))
  end

  def record_sync_time(digest)
    SourceSync.upsert({ id: 1, last_synced_at: SourceSync.wall_clock, snapshot_digest: digest }, returning: false)
  end
end

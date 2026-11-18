setup_file = ENV["CLINIC_SETUP_FILE"].presence
setup = setup_file ? JSON.parse(File.read(setup_file)) : {}

ApplicationRecord.transaction do
  Database.lock_snapshot
  now = ENV["SEED_AT"] ? Time.iso8601(ENV.fetch("SEED_AT")) : Time.current
  source_snapshot = nil
  PmsSnapshot.new.refresh(observed_at: now) do |snapshot|
    source_snapshot = snapshot
    setup.fetch("reporting_clinics", []).each do |clinic|
      ReportingClinicZone.find_or_create_by!(clinic_id: clinic.fetch("id")) do |zone|
        zone.timezone = Time.find_zone!(clinic.fetch("timezone")).name
      end
    end

    setup.fetch("messaging_clinics", []).each do |clinic|
      clinic_id = clinic.fetch("id")
      ClinicSetting.find_or_create_by!(clinic_id: clinic_id) do |setting|
        setting.timezone = Time.find_zone!(clinic.fetch("timezone")).name
        setting.sender = clinic.fetch("sender")
      end
      clinic.fetch("staff").each do |name|
        StaffMember.find_or_create_by!(clinic_id: clinic_id, name: name)
      end
    end
  end

  if ENV["ASSESSMENT_REMINDERS_START"].present?
    require_relative "assessment_history"
    require_relative "assessment_task_examples"
    require_relative "assessment_patient_details"
    AssessmentTaskExamples.new(now: now).replay
    AssessmentPatientDetails.new(now: now, source_snapshot: source_snapshot).replay
    AssessmentHistory.new(launch: Date.iso8601(ENV.fetch("ASSESSMENT_REMINDERS_START")), now: now).replay
  end
end

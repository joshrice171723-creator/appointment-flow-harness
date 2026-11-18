class PatientDetailVerification < ApplicationRecord
  self.table_name = "desk.patient_detail_verifications"

  FIELDS = {
    "birthdate" => "Birthdate",
    "wireless_phone" => "Mobile phone",
    "email" => "Email",
    "preferred_language" => "Preferred language"
  }.freeze

  belongs_to :patient
  belongs_to :staff, class_name: "StaffMember"
  scope :active, -> { where(retired_at: nil) }
  before_validation { self.comparison_value = contact_comparison }

  def contact_comparison
    case field
    when "wireless_phone" then ContactComparison.phone(verified_value)
    when "email" then ContactComparison.email(verified_value)
    end
  end

  def self.source_value(patient, field)
    raw = patient.read_attribute(field).to_s.strip.presence
    normalized_value(field, raw) || raw
  end

  def self.review_token(patient, field, current)
    last_verification_id = current&.id || where(patient_id: patient.id, field: field).maximum(:id)
    Digest::SHA256.hexdigest(JSON.generate([
      patient.id, field, source_value(patient, field), last_verification_id, current&.aligned_at, current&.conflicted_at
    ]))
  end

  # Caller owns the app transaction and the exclusive snapshot lock.
  def self.record!(patient:, staff:, field:, value:, token:, at: Time.current)
    raise ReminderFlow::Conflict, "Choose a patient detail to verify." unless FIELDS.key?(field)
    verified = normalized_value(field, value)
    unless verified && (field != "birthdate" || Date.iso8601(verified) <= at.to_date)
      raise ReminderFlow::Conflict, "Enter a valid #{FIELDS.fetch(field).downcase}."
    end

    current = patient.active_detail_verifications.find_by(field: field)
    unless token == review_token(patient, field, current)
      raise ReminderFlow::Conflict, "This detail changed while you were reviewing it. Reload patient details before saving."
    end

    pms_value = source_value(patient, field)
    current&.update!(retired_at: at)
    create!(patient: patient, staff: staff, field: field, pms_value: pms_value,
      verified_value: verified, verified_at: at, aligned_at: (at if verified == pms_value))
  end

  def reconcile_source!(at:)
    incoming = self.class.source_value(patient, field)
    expected = aligned_at ? verified_value : pms_value
    if incoming == verified_value
      update!(aligned_at: at, conflicted_at: nil) if !aligned_at || conflicted_at
    elsif incoming != expected && !conflicted_at
      update!(conflicted_at: at)
    end
  end

  def supplies_local_value?
    !aligned_at && !conflicted_at
  end

  private_class_method def self.normalized_value(field, value)
    return unless value.is_a?(String) && value.bytesize <= 254

    case field
    when "birthdate"
      return unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value).iso8601
    when "wireless_phone"
      ContactPolicy.new(Time.current).phone(value)
    when "email"
      ContactPolicy.new(Time.current).address(value)
    when "preferred_language"
      language = value.strip.downcase.tr("_", "-")
      language if language.match?(/\A\p{L}+(?:[ -]\p{L}+)*\z/)
    end
  rescue ArgumentError
    nil
  end
end

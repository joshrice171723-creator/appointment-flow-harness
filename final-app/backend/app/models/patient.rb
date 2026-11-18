class Patient < PmsRecord
  self.table_name = "pms.patients"
  belongs_to :guarantor, class_name: "Patient", optional: true
  has_many :appointments
  has_many :contact_permissions
  has_many :active_detail_verifications, -> { active }, class_name: "PatientDetailVerification"

  def effective_detail(field)
    verification = active_detail_verifications.find { |detail| detail.field == field }
    return read_attribute(field) unless verification&.supplies_local_value?

    field == "birthdate" ? Date.iso8601(verification.verified_value) : verification.verified_value
  end

  def contact_details_conflicted?
    active_detail_verifications.any?(&:conflicted_at)
  end

  def contact_permission_for(clinic_id)
    contact_permissions.find { |permission| permission.clinic_id == clinic_id }
  end

  def display_name
    "#{first_name} #{last_name}"
  end
end

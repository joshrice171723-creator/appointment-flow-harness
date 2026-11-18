class ClinicSerializer
  def self.as_json(clinic)
    clinic.attributes.slice("id", "name", "city", "state").merge(
      "timezone" => clinic.setting.timezone, "sender" => clinic.setting.sender
    )
  end
end

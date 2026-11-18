# Candidate lookup only. ContactPolicy still selects the authorized adult.
module ContactComparison
  def self.phone(value)
    ContactPolicy.new(Time.current).phone(value)
  end

  def self.email(value)
    ContactPolicy.new(Time.current).address(value)&.downcase
  end

  def self.patient_values(row)
    phone = phone(row["wireless_phone"])
    { "comparison_phone" => phone, "comparison_email" => email(row["email"]),
      "phone_quality" => row["wireless_phone"].blank? ? "missing" : (phone ? "valid" : "invalid") }
  end
end

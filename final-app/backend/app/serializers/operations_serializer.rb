class OperationsSerializer
  def initialize(rows:, clinics:, month:)
    @rows = rows
    @clinics = clinics
    @month = month
  end

  def as_json
    {
      rows: @rows.map do |row|
        row.slice(
          "clinic_id", "clinic", "outcome_month", "total", "completed",
          "canceled", "rescheduled", "unknown", "messaged", "replied",
          "messages_sent", "patient_confirmed", "follow_up", "contact_holds"
        )
      end,
      clinics: @clinics.map do |clinic|
        clinic.slice("id", "name", "messaging_available")
      end,
      activity_month: @month.strftime("%Y-%m"),
      workspace: "Apex leadership"
    }
  end
end

class AppointmentSerializer
  def initialize(visit:, hold:, issues:, appointment: nil, patient_reply: nil)
    @visit = visit
    @appointment = appointment
    @hold = hold
    @issues = issues
    @patient_reply = patient_reply
  end

  def as_json
    reply = @patient_reply&.attributes&.slice("case_id", "body")
    issues = @issues&.map { |issue| issue.attributes.slice("visit_id", "case_id", "code") }
    fields = {
      "appointment_id" => @visit&.appointment_id || @appointment.id,
      "patient_id" => @visit ? @visit.patient&.id : @appointment.patient_id,
      "start_at" => @visit&.start_at || @appointment.start_at,
      "confirmed_at" => @visit&.confirmed_at,
      "name" => @visit ? @visit.patient_name : @appointment.patient.display_name,
      "provider_name" => @visit ? @visit.provider_name : @appointment.provider_name,
      "declined_reply" => (reply if reply && ReplyClassification.call(reply.fetch("body")) == :decline),
      "patient_reply" => reply,
      "hold" => @hold,
      "reply" => issues&.find { |issue| %w[patient ambiguous_reply].include?(issue["code"]) },
      "follow_up" => issues&.first
    }
    if @appointment
      fields.merge!("status" => @appointment.status, "outcome" => @appointment.outcome)
    end
    fields
  end
end

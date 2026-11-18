class PatientsController < ApplicationController
  REPLY_REQUEST_KEY_BYTES = 16

  def patient_inbox
    require_access(session[:patient])
    clinics = Clinic.messaging_enabled.map { |clinic| clinic.slice("id", "name") }
    clinic_id = params[:clinic].presence&.to_i
    patient_id = params[:patient].presence&.to_i
    require_access(clinics.any? { |clinic| clinic["id"] == clinic_id }) if clinic_id
    permissions = ContactPermission.where(clinic_id: clinic_id)
    require_access(permissions.exists?(patient_id: patient_id)) if patient_id

    messages = Message.sent.conversation(clinic_id, patient_id).includes(:events).order(id: :desc)
    payload = PatientInboxSerializer.new(messages).as_json.merge(
      clinics: clinics, key: SecureRandom.hex(REPLY_REQUEST_KEY_BYTES)
    )
    if !patient_id || params[:include_patients] != "0"
      payload[:patients] = permissions.includes(:patient).order(:patient_id).map do |permission|
        { "clinic_id" => permission.clinic_id, "id" => permission.patient_id, "name" => permission.patient.display_name }
      end
    end
    render json: payload
  end

  def reply
    require_access(session[:patient])
    receipt = Message.sent.find_by(token: params[:token])
    require_access(receipt)
    refresh_source_if_stale

    result = ReceiveReply.new(now: Time.current).reply_to_receipt(
      receipt: receipt, text: params[:body].to_s.strip, request_key: params[:key].to_s
    )
    render json: { message: result }
  end

  private

  def refresh_source_if_stale
    PmsSnapshot.new.refresh_if_stale
  rescue ReminderFlow::Conflict => error
    # Replies can still be recorded for staff review when the source is unavailable.
    Rails.logger.warn(error.message)
  end
end

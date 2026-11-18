module PmsReplica
  CONNECTION_TIMEOUT_SECONDS = 3
  STATEMENT_TIMEOUT_SECONDS = 15
  COLUMNS = {
    "clinics" => %w[id name address_line city state phone],
    "patients" => %w[id first_name last_name birthdate wireless_phone email preferred_language guarantor_id],
    "appointments" => %w[id patient_id clinic_id provider_name start_at length_minutes procedure_note status updated_at]
  }.freeze

  class Record < ActiveRecord::Base
    self.abstract_class = true
    establish_connection(
      url: ENV.fetch("PMS_READER_URL", "postgresql://pms_reader@127.0.0.1:55439/apex_pms_contact_demo"),
      connect_timeout: CONNECTION_TIMEOUT_SECONDS,
      variables: { statement_timeout: STATEMENT_TIMEOUT_SECONDS * 1000 }
    )
    def readonly? = true
  end

  class Clinic < Record
    self.table_name = "pms.clinics"
  end

  class Patient < Record
    self.table_name = "pms.patients"
  end

  class Appointment < Record
    self.table_name = "pms.appointments"
    self.skip_time_zone_conversion_for_attributes = [:start_at, :updated_at]
  end

  def self.read(appointments_since: nil, appointment_ids: [])
    url = ENV.fetch("PMS_READER_URL", "postgresql://pms_reader@127.0.0.1:55439/apex_pms_contact_demo")
    if @reader_url != url
      Record.establish_connection(url: url, connect_timeout: CONNECTION_TIMEOUT_SECONDS,
        variables: { statement_timeout: STATEMENT_TIMEOUT_SECONDS * 1000 })
      @reader_url = url
    end
    Record.uncached do
      Record.transaction(isolation: :repeatable_read) do
        # Connection policy supplements the source account's SELECT-only grants.
        Record.connection.execute("SET TRANSACTION READ ONLY")
        appointments = Appointment.all
        if appointments_since
          appointments = appointments.where(start_at: appointments_since..)
            .or(Appointment.where(id: appointment_ids))
        end
        { "clinics" => source_rows(Clinic.order(:id), COLUMNS.fetch("clinics")),
          "patients" => source_rows(Patient.order(:id), COLUMNS.fetch("patients")),
          "appointments" => source_rows(appointments.order(:id), COLUMNS.fetch("appointments")) }
      end
    end
  rescue ActiveRecord::ActiveRecordError, PG::Error => error
    source_error = error
    source_error = source_error.cause while source_error.cause
    raise ReminderFlow::Conflict, "PMS snapshot unavailable: #{source_error.class}."
  end

  def self.source_rows(records, columns)
    records.pluck(*columns).map do |values|
      columns.zip(values).to_h.transform_values do |value|
        case value
        when Time then PmsTimestamp.text(value)
        when Date then value.iso8601
        else value
        end
      end
    end
  end
  private_class_method :source_rows

end

class ContactProfilesQuery
  def self.scope(clinic_id, patient_ids: nil)
    booked = Appointment.for_clinic(clinic_id)
    tracked = Visit.for_clinic(clinic_id)
    if patient_ids
      booked = booked.where(patient_id: patient_ids)
      tracked = tracked.where(patient_id: patient_ids)
    end
    booked = booked.select(:patient_id)
    tracked = tracked.select(:patient_id)
    patients = Patient.where(id: booked).or(Patient.where(id: tracked))
    patient_ids ? patients.where(id: patient_ids) : patients
  end

  def self.call(clinic_id, patient_id: nil)
    patients = scope(clinic_id, patient_ids: patient_id)
    patients.includes(:active_detail_verifications,
      contact_permissions: { authorized_guarantor: :active_detail_verifications }).to_a
  end

  def self.sharing_destination(clinic_id, channel:, destination:, except:)
    return enum_for(__method__, clinic_id, channel: channel, destination: destination, except: except) unless block_given?
    field, column, value = if channel == "SMS"
      ["wireless_phone", :comparison_phone, ContactComparison.phone(destination)]
    else
      ["email", :comparison_email, ContactComparison.email(destination)]
    end
    return unless value

    local_details = PatientDetailVerification.active.where(field: field, comparison_value: value,
      aligned_at: nil, conflicted_at: nil).select(:patient_id)
    [Patient.where(column => value), Patient.where(id: local_details)].each do |contacts|
      contacts.in_batches(of: 100) do |batch|
        contact_ids = batch.pluck(:id)
        dependents = ContactPermission.where(clinic_id: clinic_id, authorized_guarantor_id: contact_ids)
          .select(:patient_id)
        [contact_ids, dependents].each do |ids|
          scope(clinic_id, patient_ids: ids).where.not(id: except).includes(:active_detail_verifications,
            contact_permissions: { authorized_guarantor: :active_detail_verifications })
            .find_each(batch_size: 100) { |patient| yield patient }
        end
      end
    end
  end
end

class ContactPermission < ApplicationRecord
  self.table_name = "desk.people"
  self.primary_key = [:patient_id, :clinic_id]
  belongs_to :patient
  belongs_to :authorized_guarantor, class_name: "Patient", optional: true
end

class ClinicSetting < ApplicationRecord
  self.table_name = "desk.clinic_settings"
  self.primary_key = :clinic_id
end

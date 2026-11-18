class Clinic < PmsRecord
  self.table_name = "pms.clinics"
  has_one :setting, class_name: "ClinicSetting"
  has_one :reporting_zone, class_name: "ReportingClinicZone"
  has_many :appointments

  scope :messaging_enabled, -> { joins(:setting).includes(:setting).order(:id) }
end

class Message < ApplicationRecord
  self.table_name = "desk.messages"
  has_many :items, class_name: "MessageItem"
  has_many :visits, through: :items
  has_many :events, class_name: "ActivityEvent"
  scope :sent, -> { where(status: "sent") }
  scope :conversation, ->(clinic, patient) { where(clinic_id: clinic, patient_id: patient) }
end

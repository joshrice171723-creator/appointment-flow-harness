class MessageItem < ApplicationRecord
  self.table_name = "desk.message_items"
  self.primary_key = [:visit_id, :purpose]
  belongs_to :message
  belongs_to :visit
end

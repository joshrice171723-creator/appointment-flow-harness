class OptOut < ApplicationRecord
  self.table_name = "desk.opt_outs"
  self.primary_key = [:clinic_id, :destination]
end

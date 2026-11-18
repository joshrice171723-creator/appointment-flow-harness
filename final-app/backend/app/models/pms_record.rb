# These models read the local source cache. Only PmsSnapshot imports into it.
class PmsRecord < ApplicationRecord
  self.abstract_class = true

  def readonly? = true
end

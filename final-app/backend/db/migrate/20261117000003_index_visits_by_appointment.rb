class IndexVisitsByAppointment < ActiveRecord::Migration[8.1]
  def change
    add_index "desk.visits", :appointment_id, name: :visit_appointment
  end
end

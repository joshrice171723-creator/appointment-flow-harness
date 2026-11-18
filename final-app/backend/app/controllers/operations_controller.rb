class OperationsController < ApplicationController
  def operations
    require_access(session[:operations] == true)
    month = params[:month]
    if month && !(month.is_a?(String) && (month == "current" || month.match?(/\A[1-9]\d{3}-(?:0[1-9]|1[0-2])\z/)))
      raise ReminderFlow::Conflict, "Choose a valid outcome month."
    end

    render json: OperationsQuery.call(month: month)
  end
end

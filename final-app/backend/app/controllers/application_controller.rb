class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  rescue_from ReminderFlow::Conflict do |error|
    render json: { error: error.message }, status: :conflict
  end
  rescue_from ActionController::InvalidAuthenticityToken do
    render json: { error: "Refresh this page and try again." }, status: :unprocessable_entity
  end

  private

  def require_access(value)
    raise ReminderFlow::Conflict, "Open the appropriate workspace first." unless value
  end
end

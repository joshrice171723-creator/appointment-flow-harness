class WorkspacesController < ApplicationController
  def index
    render html: <<~HTML.html_safe
      <!doctype html><html lang="en"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Appointment Flow</title>#{view_context.csrf_meta_tags}
      <link rel="stylesheet" href="/flow.css"></head>
      <body><div id="root"></div><script defer src="/application.js"></script></body></html>
    HTML
  end

  def workspaces
    render json: {
      clinics: Clinic.messaging_enabled.map { |clinic| ClinicSerializer.as_json(clinic) },
      staff: StaffMember.order(:id).map(&:attributes), reporting_clinic_count: Clinic.count, now: Time.current
    }
  end

  def enter
    case params[:workspace]
    when "desk"
      clinic = Clinic.messaging_enabled.find_by(id: params[:clinic].to_i)
      staff = StaffMember.find_by(id: params[:staff].to_i)
      require_access(clinic && staff && clinic.id == staff.clinic_id)
      switch_workspace
      session[:staff] = staff.id
      render json: { path: "/front-desk?clinic=#{clinic.id}" }
    when "apex"
      switch_workspace
      session[:operations] = true
      render json: { path: "/operations" }
    when "patient"
      switch_workspace
      session[:patient] = true
      render json: { path: "/patient" }
    else
      raise ReminderFlow::Conflict, "Choose a workspace."
    end
  end

  private

  def switch_workspace
    %i[staff operations patient].each { |role| session.delete(role) }
  end
end

Rails.application.routes.draw do
  # Browser pages share the React app shell.
  root "workspaces#index"
  get "/front-desk",   to: "workspaces#index"
  get "/appointments", to: "workspaces#index"
  get "/work/:id",     to: "workspaces#index"
  get "/patient-details/:id", to: "workspaces#index"
  get "/patient",      to: "workspaces#index"
  get "/operations",   to: "workspaces#index"

  # API: workspace selection
  get  "/api/workspaces", to: "workspaces#workspaces"
  post "/api/enter",      to: "workspaces#enter"

  # API: front desk
  get  "/api/appointments", to: "desk#appointments"
  get  "/api/board",        to: "desk#board"
  get  "/api/work/:id",     to: "desk#case_detail"
  post "/api/work/:id",     to: "desk#work"
  get  "/api/patient-details/:id", to: "desk#patient_details"
  post "/api/patient-details/:id", to: "desk#verify_patient_detail"
  get  "/api/patient-details/:id/history", to: "desk#patient_history"

  # API: patient inbox and replies
  get  "/api/patient",                 to: "patients#patient_inbox"
  post "/api/patient/messages/:token", to: "patients#reply"

  # API: leadership
  get "/api/operations", to: "operations#operations"

end

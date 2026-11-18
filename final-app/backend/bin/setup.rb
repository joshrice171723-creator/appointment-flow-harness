require_relative "../config/environment"
require_relative "setup_replica"

# Database creation needs the setup account; migrations and seeds use the app account.
runtime = URI(ENV.fetch("DENTAL_DATABASE_URL", Database::APP_URL))
admin = URI(ENV.fetch("APP_ADMIN_URL", "postgresql://desk@127.0.0.1:55439/postgres"))
name = runtime.path.delete_prefix("/")
role = URI.decode_www_form_component(runtime.user)
Database.provision(admin.to_s) do |db|
  unless db.exec_params("SELECT 1 FROM pg_roles WHERE rolname=$1", [role]).ntuples.positive?
    password = runtime.password ? " PASSWORD #{db.escape_literal(URI.decode_www_form_component(runtime.password))}" : ""
    db.exec("CREATE ROLE #{db.quote_ident(role)} LOGIN#{password}")
  end
  unless db.exec_params("SELECT 1 FROM pg_database WHERE datname=$1", [name]).ntuples.positive?
    db.exec("CREATE DATABASE #{db.quote_ident(name)} OWNER #{db.quote_ident(role)}")
  end
end

ActiveRecord::Base.establish_connection(runtime.to_s)
ActiveRecord::Base.connection_pool.migration_context.migrate
load Rails.root.join("db/seeds.rb")

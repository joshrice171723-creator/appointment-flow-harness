require "bundler/setup"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "sidekiq"
require "sidekiq-cron"
require_relative "../infrastructure/database"

module AppointmentFlow
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    config.log_level = :info
    config.active_record.dump_schemas = 'pms,desk'
    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") { SecureRandom.hex(64) }
    config.session_store :cookie_store, key: "_appointment_flow", same_site: :lax
    config.public_file_server.enabled = true
    config.filter_parameters += %i[body note key token verified_value]
    config.logger = ActiveSupport::Logger.new($stderr)
  end
end

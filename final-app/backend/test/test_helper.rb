ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require_relative "unit_test_helper"
require "rack/test"
require "pg"
require "active_support/testing/time_helpers"
require_relative "workflow_fixture"

app_database = URI(ENV.fetch("DENTAL_DATABASE_URL"))
abort "Use a disposable app database ending in _test." unless app_database.path.end_with?("_test")

# Disposable source records are independent of the running demo.
source_admin = URI(ENV.fetch("APP_ADMIN_URL", "postgresql://desk@127.0.0.1:55439/postgres"))
source_admin.path = app_database.path + "_source_test"
source_reader = URI(ENV.fetch("PMS_READER_URL", "postgresql://pms_reader@127.0.0.1:55439/apex_pms_contact_demo"))
source_reader.path = source_admin.path
ENV["PMS_ADMIN_URL"] = source_admin.to_s
ENV["PMS_READER_URL"] = source_reader.to_s
ENV["SEED_AT"] = TEST_NOW.iso8601
# Rebuild both disposable schemas so an old fixture cannot hide seed changes.
app_admin = URI(ENV.fetch("APP_ADMIN_URL"))
app_admin.path = app_database.path
catalog = source_admin.dup
catalog.path = "/postgres"
source_name, app_name = [source_admin, app_admin].map { |url| url.path.delete_prefix("/") }
existing = PG.connect(catalog.to_s) do |db|
  db.exec_params("SELECT datname FROM pg_database WHERE datname IN ($1, $2)", [source_name, app_name]).column_values(0)
end
if existing.include?(source_name)
  PG.connect(source_admin.to_s) { |db| db.exec("DROP SCHEMA IF EXISTS pms CASCADE; DROP TABLE IF EXISTS public.schema_migrations; DROP TABLE IF EXISTS public.ar_internal_metadata") }
end
if existing.include?(app_name)
  PG.connect(app_admin.to_s) do |db|
    db.exec("DROP SCHEMA IF EXISTS desk CASCADE; DROP SCHEMA IF EXISTS pms CASCADE; DROP TABLE IF EXISTS public.schema_migrations; DROP TABLE IF EXISTS public.ar_internal_metadata")
  end
end
ENV.delete("CLINIC_SETUP_FILE")
ENV.delete("ASSESSMENT_REMINDERS_START")
load Rails.root.join("bin/setup.rb")
ApplicationRecord.transaction { WorkflowFixture.load(now: TEST_NOW) }

class Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  # Capture the real setup once, before randomized tests can change it.
  models = [Clinic, Patient, Appointment, ClinicSetting, ReportingClinicZone,
            StaffMember, ContactPermission, PatientDetailVerification, DemoState, SourceSync, Visit,
            FollowUpCase, Message, MessageItem, ActivityEvent, FollowUpIssue, OptOut, IssueCandidate, AppointmentHistory]
  class_attribute :demo_fixture_rows, default: models.to_h { |model|
    generated = model.columns.select(&:virtual?).map(&:name)
    [model, model.all.map { |record| record.attributes.except(*generated) }]
  }
  class_attribute :demo_fixture_dirty, default: false
  class_attribute :committed_demo_tests, default: []
  class_attribute :unpinned_rollback_tests, default: []

  def restore_demo_fixture
    committed = self.class.committed_demo_tests.include?(name)
    if Minitest::Test.demo_fixture_dirty
      Database.open do |db|
        db.transaction do
          WorkflowFixture.clear
          Minitest::Test.demo_fixture_rows.each do |model, rows|
            model.insert_all!(rows.map(&:dup)) unless rows.empty?
          end
        end
      end
      Minitest::Test.demo_fixture_dirty = false
    end

    if committed
      # Workers and transaction-ownership checks must see actual commits.
      Minitest::Test.demo_fixture_dirty = true
    elsif !self.class.unpinned_rollback_tests.include?(name)
      # Use Rails' fixture transaction so Rack requests keep the same database connection.
      @demo_fixture_pool = ApplicationRecord.connection_pool
      @demo_fixture_pool.pin_connection!(true)
      @demo_fixture_pool.lease_connection
    end
    # Each test starts fresh even if earlier tests took longer than the cache lifetime.
    SourceSync.where(id: 1).update_all(last_synced_at: Arel.sql("clock_timestamp()"))
  end

  def with_replica(snapshot)
    original = PmsReplica.method(:read)
    PmsReplica.define_singleton_method(:read) { |**| snapshot }
    yield
  ensure
    PmsReplica.define_singleton_method(:read, original)
  end

  def before_setup
    super
    travel_to(TEST_NOW)
  end

  def after_teardown
    if @demo_fixture_pool && !@demo_fixture_pool.unpin_connection!
      Minitest::Test.demo_fixture_dirty = true
    end
  ensure
    travel_back
    super
  end
end

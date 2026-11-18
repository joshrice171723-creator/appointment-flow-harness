require_relative "test_helper"
require "timeout"

class RequestFailureContractTest < Minitest::Test
  include Rack::Test::Methods

  self.committed_demo_tests = %w[
    test_returned_conflict_commits_refresh_and_reconciliation
    test_raised_rejection_rolls_back_action_but_keeps_refresh
    test_access_is_checked_again_after_refresh
    test_access_is_checked_after_waiting_for_the_clinic_lock
  ]

  def app = Rails.application

  def setup
    restore_demo_fixture
    get "/"
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
  end

  def enter(workspace, **options)
    post "/api/enter", JSON.generate(workspace: workspace, **options)
    assert_equal 200, last_response.status
  end

  def test_out_of_scope_staff_action_does_not_read_the_source
    entry = FollowUpCase.find_by!(patient_id: 102, clinic_id: 1)
    ClinicSetting.create!(clinic_id: 5, timezone: "America/Phoenix", sender: "+16025550100")
    staff = StaffMember.create!(clinic_id: 5, name: "Other clinic staff")
    enter("desk", clinic: 5, staff: staff.id)
    with_replica(nil) do
      post "/api/work/#{entry.id}", JSON.generate(outcome: "confirmed", version: entry.version)
    end
    assert_equal 409, last_response.status
    assert_equal "Open the appropriate workspace first.", JSON.parse(last_response.body).fetch("error")
  end

  def test_invalid_receipt_does_not_refresh_the_source
    enter("patient")
    snapshot = PmsReplica.read
    snapshot.fetch("clinics").first["name"] = "Must not import"
    SourceSync.where(id: 1).update_all(last_synced_at: 1.day.ago)
    with_replica(snapshot) do
      post "/api/patient/messages/missing-token", JSON.generate(body: "YES", key: "invalid-receipt")
    end
    assert_equal 409, last_response.status
    refute Clinic.exists?(name: "Must not import")
  end

  def test_returned_conflict_commits_refresh_and_reconciliation
    enter("desk", clinic: 1, staff: 11)
    entry = FollowUpCase.find_by!(patient_id: 102, clinic_id: 1)
    visit = Visit.current.find_by!(appointment_id: 102)
    snapshot = PmsReplica.read
    snapshot.fetch("appointments").find { |row| row.fetch("id") == 102 }["status"] = "complete"
    with_replica(snapshot) do
      post "/api/work/#{entry.id}", JSON.generate(outcome: "confirmed", version: entry.version)
    end
    assert_equal 409, last_response.status
    assert_equal "This case changed. Refresh it before acting.", JSON.parse(last_response.body).fetch("error")
    assert_equal "complete", Appointment.find(102).status
    assert_equal "resolved", entry.reload.state
    refute visit.reload.current
  end

  def test_raised_rejection_rolls_back_action_but_keeps_refresh
    enter("desk", clinic: 1, staff: 11)
    entry = FollowUpCase.find_by!(patient_id: 102, clinic_id: 1)
    post "/api/work/#{entry.id}", JSON.generate(outcome: "claim", version: entry.version)
    assert_equal 200, last_response.status
    snapshot = PmsReplica.read
    appointment = snapshot.fetch("appointments").find { |row| row.fetch("id") == 123 }
    moved_start_at = Appointment.find(123).start_at + 1.hour
    appointment["start_at"] = moved_start_at.strftime("%FT%T")
    visit = Visit.current.find_by!(appointment_id: 123)
    events_before = ActivityEvent.count
    with_replica(snapshot) do
      post "/api/work/#{entry.id}", JSON.generate(outcome: "confirmed", version: entry.reload.version, note: "")
    end
    assert_equal 409, last_response.status
    assert_equal "Choose an action and record what happened.", JSON.parse(last_response.body).fetch("error")
    assert_equal moved_start_at, Appointment.find(123).start_at
    assert visit.reload.current, "Reconciliation belongs to the rejected action transaction"
    assert_equal events_before, ActivityEvent.count
  end

  def test_access_is_checked_again_after_refresh
    enter("desk", clinic: 1, staff: 11)
    entry = FollowUpCase.find_by!(patient_id: 102, clinic_id: 1)
    snapshot = PmsReplica.read
    original = PmsReplica.method(:read)
    PmsReplica.define_singleton_method(:read) do |**|
      StaffMember.where(id: 11).update_all(clinic_id: 5)
      snapshot
    end
    post "/api/work/#{entry.id}", JSON.generate(outcome: "confirmed", version: entry.version)
    assert_equal 409, last_response.status
    assert_equal "Open the appropriate workspace first.", JSON.parse(last_response.body).fetch("error")
  ensure
    PmsReplica.define_singleton_method(:read, original) if original
  end

  def test_access_is_checked_after_waiting_for_the_clinic_lock
    enter("desk", clinic: 1, staff: 11)
    entry = FollowUpCase.find_by!(patient_id: 102, clinic_id: 1)
    form = JSON.generate(outcome: "claim", version: entry.version)
    client = rack_test_session
    request = nil

    ApplicationRecord.transaction do
      Database.lock_clinic(1)
      request = Thread.new { client.post("/api/work/#{entry.id}", form) }
      wait_for_clinic_lock
      StaffMember.find(11).update!(clinic_id: 5)
    end

    response = request.value
    assert_equal 409, response.status
    assert_equal "Open the appropriate workspace first.", JSON.parse(response.body).fetch("error")
    assert_nil entry.reload.owner_id
    refute entry.events.exists?(kind: "claim")
  ensure
    request&.join
  end

  private

  def wait_for_clinic_lock
    sql = <<~SQL
      SELECT EXISTS (
        SELECT FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted AND objsubid = 2
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND classid = #{Database::CLINIC_LOCK_NAMESPACE} AND objid = 1
      )
    SQL
    Timeout.timeout(10) do
      sleep(0.01) until ApplicationRecord.connection.select_value(sql)
    end
  end
end

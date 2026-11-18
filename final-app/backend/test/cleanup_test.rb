require_relative "test_helper"

class CleanupTest < Minitest::Test
  self.unpinned_rollback_tests = %w[test_invalid_snapshot_preserves_cached_records_and_freshness]
  self.committed_demo_tests = %w[test_repeating_migrations_and_seeds_does_not_duplicate_or_reset_demo_records]

  include Rack::Test::Methods

  def app = Rails.application

  def setup
    restore_demo_fixture
    get "/"
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
  end

  def test_wording_does_not_control_contact_work
    Database.open do |db|
      db.transaction do
        flow = ReminderFlow.new
        ReconcileAppointments.new(now: flow.now).for_clinic(1)
        visit = flow.load_visits(1).find { |row| row["patient_id"] == 104 }
        assert_equal :no_contact, flow.contact_policy.hold_code(visit)
        flow.contact_policy.define_singleton_method(:hold) { |_record, **_options| "Contact details are unavailable." }
        flow.run(1)
        issue = db.first_row("SELECT code,reason FROM desk.issues WHERE visit_id=$1", visit.id)
        assert_equal ["contact", ContactPolicy::ISSUE_REASONS.fetch(:missing_phone)], issue.values_at("code", "reason")
        assert_nil db.first_row("SELECT 1 FROM desk.message_items WHERE visit_id=$1", visit.id)

        contact_issue = FollowUpIssue.find_by!(visit_id: visit.id, code: "contact")
        follow_up = contact_issue.follow_up_case
        staff = StaffMember.find(11)
        source_before = visit.patient.attributes
        RecordFollowUp.new(version: follow_up.version, outcome: "claim")
          .record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: flow.now)
        RecordFollowUp.new(version: follow_up.reload.version, outcome: "attempted",
          issue_id: contact_issue.id, note: "Tried to reach the patient.")
          .record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: flow.now)
        assert_nil contact_issue.reload.resolved_at

        RecordFollowUp.new(version: follow_up.reload.version, outcome: "confirmed",
          issue_id: contact_issue.id, note: "Confirmed in person.")
          .record_action_on_reconciled_case(follow_up: follow_up, staff: staff, now: flow.now)
        flow.run(1)
        assert contact_issue.reload.resolved_at
        assert_equal "confirmed", contact_issue.resolution_event.kind
        assert_equal source_before, Patient.find(visit.patient_id).attributes
        assert_equal :no_contact, flow.contact_policy.hold_code(Visit.with_context.find(visit.id))
        refute visit.messages.sent.exists?
      end
    end
  end

  def test_invalid_snapshot_preserves_cached_records_and_freshness
    Database.open do |db|
      snapshot = PmsSnapshot::COLUMNS.to_h { |table, _| [table, db.rows("SELECT * FROM pms.#{table}")] }
      before = db.rows("SELECT * FROM pms.clinics ORDER BY id")
      synced_at = SourceSync.status.fetch("last_synced_at")
      snapshot.fetch("clinics").first["name"] = "Must not be saved"
      invalid_payloads = [nil, [], snapshot.merge("patients" => ["bad record"]),
                          snapshot.merge("appointments" => [false])]

      invalid_payloads.each do |payload|
        with_replica(payload) do
          # Import owns atomicity even when its caller supplies no transaction.
          assert_raises(ReminderFlow::Conflict) { PmsSnapshot.new.refresh }
        end
        assert_equal before, db.rows("SELECT * FROM pms.clinics ORDER BY id")
        assert_equal synced_at, SourceSync.status.fetch("last_synced_at")
      end
    end
  end

  def test_flow_uses_real_time
    assert_equal TEST_NOW, ReminderFlow.new.now
    travel_to(TEST_NOW + 1.hour)
    assert_equal TEST_NOW + 1.hour, ReminderFlow.new.now
  end

  def test_inbox_only_returns_the_selected_conversation
    post "/api/enter", JSON.generate(workspace: "patient")
    get "/api/patient"
    directory = JSON.parse(last_response.body)
    assert_empty directory.fetch("messages")
    assert_empty directory.fetch("patients")
    get "/api/patient", clinic: 1, patient: 102
    assert_equal 200, last_response.status
    inbox = JSON.parse(last_response.body)
    assert_equal [102], inbox.fetch("messages").map { |message| message.fetch("patient_id") }.uniq
    tokens = inbox.fetch("messages").map { |message| message.fetch("token") }
    assert inbox.fetch("replies").all? { |reply| tokens.include?(reply.fetch("token")) }
    get "/api/patient", clinic: 5, patient: 102
    assert_equal 409, last_response.status
  end

  def test_repeating_migrations_and_seeds_does_not_duplicate_or_reset_demo_records
    before = [Message.count, ActivityEvent.count, FollowUpCase.count, DemoState.find(1).seeded_at]
    # Migration filenames use wall-clock time; the frozen visit date predates this migration.
    travel_back do
      ActiveRecord::Base.connection_pool.migration_context.migrate
      load Rails.root.join("db/seeds.rb")
      assert_empty ActiveRecord::Base.connection_pool.migration_context.open.pending_migrations
    end
    assert_equal before, [Message.count, ActivityEvent.count, FollowUpCase.count, DemoState.find(1).seeded_at]
  end
end

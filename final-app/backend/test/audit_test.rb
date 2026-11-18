require_relative "test_helper"

class AuditTest < Minitest::Test
  include Rack::Test::Methods

  def app = Rails.application

  def setup
    restore_demo_fixture
    get "/"
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
  end

  def enter(workspace, **options)
    post "/api/enter", JSON.generate(workspace: workspace, **options)
  end

  def test_calendar_decline_requires_a_whole_message_and_keeps_other_replies
    enter("desk", clinic: 1, staff: 11)
    ["NO", " no! ", "No, I can't make it", "No problem, I'll be there", "Yes, but call me."].each do |text|
      Database.open do |db|
        db.exec_params(<<~SQL, [text])
          UPDATE desk.events SET body=$1 WHERE kind='reply'
            AND visit_id IN (SELECT id FROM desk.visits WHERE appointment_id=102)
        SQL
      end
      get "/api/appointments", clinic: 1, date: "2026-11-06"
      assert_equal 200, last_response.status
      visit = JSON.parse(last_response.body).fetch("visits").find { |row| row["appointment_id"] == 102 }
      assert_equal text, visit.fetch("patient_reply").fetch("body")
      assert_equal ["NO", " no! ", "No, I can't make it"].include?(text), !visit["declined_reply"].nil?
      assert visit.fetch("reply")
      assert_nil visit.fetch("confirmed_at")
    end
  end

  def test_gets_do_not_reconcile_but_the_worker_does_without_sending_early
    travel_to(TEST_NOW - 5.minutes)
    snapshot = PmsReplica.read
    snapshot.fetch("appointments").find { |row| row["id"] == 102 }["status"] = "complete"
    Database.open do |db|
      db.exec("UPDATE pms.appointments SET status='complete' WHERE id=102")
      db.exec("UPDATE desk.source_sync SET last_synced_at=clock_timestamp()-interval '6 minutes'")
    end
    enter("desk", clinic: 1, staff: 11)
    case_id = Database.open { |db| db.exec("SELECT id FROM desk.cases WHERE patient_id=102").first.fetch("id") }
    before = workflow_records
    ["/api/board?clinic=1", "/api/appointments?clinic=1&date=today", "/api/work/#{case_id}"].each do |url|
      get url
      assert_equal 200, last_response.status
    end
    enter("apex")
    get "/api/operations"
    assert_equal 200, last_response.status
    assert_equal before, workflow_records

    with_replica(snapshot) { ReminderRunner.tick }
    after = workflow_records
    assert_equal before.fetch("messages"), after.fetch("messages")
    Database.open do |db|
      assert_equal "resolved", db.first_row("SELECT state FROM desk.cases WHERE id=$1", case_id).fetch("state")
      refute SourceSync.status.fetch("stale")
      assert db.first_row("SELECT 1 FROM desk.issues i JOIN desk.visits v ON v.id=i.visit_id WHERE v.patient_id=162 AND i.resolved_at IS NULL")
    end
  end

  def test_calendar_uses_imported_source_fields_before_reconciliation
    Database.open do |db|
      db.transaction { Visit.current.find_by!(appointment_id: 123).confirm!(actor: "Audit fixture", at: Time.current) }
    end
    enter("desk", clinic: 1, staff: 11)

    [{ "start_at" => "2026-11-12T17:00:00" }, { "patient_id" => 102 }].each do |change|
      snapshot = PmsReplica.read
      source = snapshot.fetch("appointments").find { |row| row.fetch("id") == 123 }
      source.merge!(change).merge!("provider_name" => "Updated provider")
      with_replica(snapshot) do
        PmsSnapshot.new.refresh
      end
      before = workflow_records

      get "/api/appointments", clinic: 1, date: source.fetch("start_at").first(10)
      assert_equal 200, last_response.status
      row = JSON.parse(last_response.body).fetch("visits").find { |visit| visit.fetch("appointment_id") == 123 }
      assert row, "The imported appointment must remain on its source calendar date."
      assert_equal source.fetch("start_at"), row.fetch("start_at").first(19)
      assert_equal "Demo Patient #{source.fetch('patient_id')}", row.fetch("name")
      assert_equal "Updated provider", row.fetch("provider_name")
      assert_nil row.fetch("confirmed_at")
      assert_nil row.fetch("reply")
      assert_equal before, workflow_records
    end
  end

  private

  def workflow_records
    Database.open do |db|
      queries = %w[visits cases issues messages events source_sync].map do |table|
        "SELECT '#{table}' AS name, md5(coalesce(json_agg(t ORDER BY id),'[]')::text) AS digest FROM desk.#{table} t"
      end
      db.exec(queries.join(" UNION ALL ")).to_h { |row| row.values_at("name", "digest") }
    end
  end
end

class MessageLanguageTest < Minitest::Test
  def test_english_variants_share_the_seed_and_live_policy
    flow = ReminderFlow.new
    [nil, "", "  ", " English ", "EN", "en-US", "EN_gb"].each { |value| assert flow.message_templates.english?(value), value.inspect }
    ["es", "fr", "enough", "en-US extra"].each { |value| refute flow.message_templates.english?(value), value }
  end
end

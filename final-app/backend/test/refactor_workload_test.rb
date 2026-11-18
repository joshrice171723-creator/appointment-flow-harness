require_relative "test_helper"
require_relative "../../docs/ai-harness/quality/rails_workload_probe"

class RefactorWorkloadTest < Minitest::Test
  include Rack::Test::Methods

  CLINIC = 991801
  PATIENT = 991801
  APPOINTMENT = 991801
  AT = Time.utc(2026, 11, 12, 12)

  def app = Rails.application

  def setup
    restore_demo_fixture
  end

  def measure(label, guardian_access: false)
    statements = []
    listener = lambda do |event|
      payload = event.payload
      if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA" && !payload[:cached]
        statements << payload.slice(:sql, :type_casted_binds)
      end
    end
    result, metrics = ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
      RailsWorkloadProbe.measure { ApplicationRecord.uncached { yield } }
    end
    output = ENV["WORKLOAD_OUTPUT"]
    if output
      File.open(output, "a") do |file|
        file.puts JSON.generate(label: label, metrics: metrics, revision: ENV["EVIDENCE_REVISION"],
          response_bytes: (last_response.body.bytesize if guardian_access))
      end
    end
    if guardian_access || (output && label.end_with?(":reply", ":history_request", ":first_batch"))
      assert statements.any? { |statement| statement[:sql].include?('"pms"."patients"."guarantor_id"') } if guardian_access
      statements.each do |statement|
        sql = statement.fetch(:sql)
        if guardian_access
          next unless sql.include?('"pms"."patients"."guarantor_id"')
        else
          next unless sql.include?("comparison_phone") || sql.include?("desk") || sql.include?("ORDER BY") && sql.include?("start_at")
        end
        binds = statement[:type_casted_binds]
        binds = binds.call if binds.respond_to?(:call)
        plan = ApplicationRecord.connection.raw_connection.exec_params(
          "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}", binds || []).first.values.first
        parsed = JSON.parse(plan)
        File.open(output + ".plans", "a") { |file| file.puts JSON.generate(label: label, query: sql, plan: parsed) } if output
        if label == "guardian_access:grown" || label.start_with?("history=1000,relevant=1:")
          assert_bounded_history_plan(parsed.first.fetch("Plan"), label, sql)
        end
      end
    end
    result
  end

  def assert_bounded_history_plan(node, label, query)
    # Returned rows alone can hide repeated probes or scans of unrelated history.
    if node["Relation Name"]
      work = (node.fetch("Actual Rows", 0) + node.fetch("Rows Removed by Filter", 0)) * node.fetch("Actual Loops", 0)
      assert_operator work, :<=, 128, "#{label}: #{node['Relation Name']} inspected #{work} rows: #{query}"
    end
    node.fetch("Plans", []).each { |child| assert_bounded_history_plan(child, label, query) }
  end

  def test_staff_guardian_history_with_unrelated_patients_and_permissions
    guardian = 7_400_001
    child = 161
    other_clinic_child = 7_400_002
    Patient.insert_all!([
      { id: guardian, first_name: "Demo", last_name: "Guardian", guarantor_id: nil },
      { id: other_clinic_child, first_name: "Demo", last_name: "Patient", guarantor_id: guardian }
    ])
    Appointment.insert_all!([{ id: other_clinic_child, patient_id: other_clinic_child, clinic_id: 5,
      start_at: TEST_NOW, status: "scheduled" }])
    ContactPermission.create!(clinic_id: 5, patient_id: other_clinic_child, authorized_guarantor_id: guardian)
    Patient.where(id: child).update_all(guarantor_id: guardian)
    permission = ContactPermission.find_by!(clinic_id: 1, patient_id: child)
    permission.update!(authorized_guarantor_id: guardian)

    get "/"
    header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
    header "Content-Type", "application/json"
    post "/api/enter", JSON.generate(workspace: "desk", clinic: 1, staff: 11)
    assert last_response.ok?, last_response.body

    path = "/api/patient-details/#{guardian}/history"
    measure("guardian_access:small", guardian_access: true) { get path, section: "appointments" }
    assert last_response.ok?, last_response.body
    assert_equal({ "rows" => [], "next_cursor" => nil }, JSON.parse(last_response.body))
    original_body = last_response.body

    unrelated_ids = (7_401_000...7_403_000).to_a
    Patient.insert_all!(unrelated_ids.map do |id|
      { id: id, first_name: "Demo", last_name: "Patient", guarantor_id: (guardian if id.even?) }
    end)
    Appointment.insert_all!(unrelated_ids.map do |id|
      { id: id, patient_id: id, clinic_id: 1, start_at: TEST_NOW - 1.month, status: "complete" }
    end)
    ContactPermission.insert_all!(unrelated_ids.map do |id|
      { patient_id: id, clinic_id: 1, sms: true, email: true }
    end)
    # Simulate aged mirror rows with up-to-date planner statistics.
    ApplicationRecord.connection.execute("ANALYZE pms.patients; ANALYZE desk.people")
    measure("guardian_access:grown", guardian_access: true) { get path, section: "appointments" }
    assert last_response.ok?, last_response.body
    assert_equal original_body, last_response.body

    Patient.where(id: child).update_all(guarantor_id: 190)
    get path, section: "appointments"
    assert_equal 409, last_response.status
    Patient.where(id: child).update_all(guarantor_id: guardian)
    permission.update!(authorized_guarantor_id: nil)
    get path, section: "appointments"
    assert_equal 409, last_response.status
  end

  def with_source_workload(history:, relevant:)
    source = PG.connect(ENV.fetch("PMS_ADMIN_URL"))
    source.exec_params("INSERT INTO pms.clinics(id,name,state) VALUES($1,'Workload clinic','TX')", [CLINIC])
    count = history + relevant
    source.exec_params(<<~SQL, [PATIENT, count])
      INSERT INTO pms.patients(id,first_name,last_name,birthdate,wireless_phone,email,preferred_language)
      SELECT $1::bigint+n,'Demo Patient',n::text,'1980-01-01','+1512'||(3000000+n),
        'workload'||n||'@example.test','en' FROM generate_series(0,$2::integer-1) n;
    SQL
    source.exec_params(<<~SQL, [APPOINTMENT, PATIENT, CLINIC, relevant, count])
      INSERT INTO pms.appointments(id,patient_id,clinic_id,start_at,status)
      SELECT $1::bigint+n,$2::bigint+n,$3,
        CASE WHEN n<$4::integer THEN '2026-11-12 12:00'::timestamp ELSE '2026-10-12 12:00' END,
        CASE WHEN n<$4::integer THEN 'scheduled' ELSE 'complete' END
      FROM generate_series(0,$5::integer-1) n;
    SQL
    source.exec("ANALYZE pms.appointments; ANALYZE pms.patients")
    yield
  ensure
    if source
      source.exec_params("DELETE FROM pms.appointments WHERE clinic_id=$1", [CLINIC])
      source.exec_params("DELETE FROM pms.patients WHERE id >= $1 AND id < $1 + $2", [PATIENT, count || 0])
      source.exec_params("DELETE FROM pms.clinics WHERE id=$1", [CLINIC])
      source.close
    end
  end

  def test_complete_import_batch_reply_and_history_under_growth
    [[0, 1], [1000, 1], [0, 25]].each do |history, relevant|
      with_source_workload(history: history, relevant: relevant) do
        ApplicationRecord.transaction(requires_new: true) do
          WorkflowFixture.clear
          prefix = "history=#{history},relevant=#{relevant}"
          snapshot = PmsReplica.read
          measure("#{prefix}:source_bytes=#{JSON.generate(snapshot).bytesize}") { snapshot }
          measure("#{prefix}:first_import") do
            PmsSnapshot.new.refresh do
              ClinicSetting.create!(clinic_id: CLINIC, timezone: "America/Chicago", sender: "+15125550198")
              StaffMember.create!(id: CLINIC, clinic_id: CLINIC, name: "Workload staff")
            end
          end
          assert_equal history + relevant, Appointment.for_clinic(CLINIC).count
          assert_equal history + relevant, ContactPermission.where(clinic_id: CLINIC).count
          ContactPermission.where(patient_id: PATIENT, clinic_id: CLINIC).update_all(email: false)
          permissions = ContactPermission.where(clinic_id: CLINIC).order(:patient_id).map(&:attributes)
          measure("#{prefix}:unchanged_import") { PmsSnapshot.new.refresh }
          assert_equal permissions, ContactPermission.where(clinic_id: CLINIC).order(:patient_id).map(&:attributes)

          populate_unrelated_history(relevant, history) if history.positive?

          flow = ReminderFlow.new(now: TEST_NOW)
          assert_equal relevant, measure("#{prefix}:first_batch") { flow.run_daily_batch(CLINIC, TEST_NOW.to_date) }
          identities = [Visit.for_clinic(CLINIC).order(:id).ids, Message.where(clinic_id: CLINIC).order(:id).ids]
          assert_equal 0, measure("#{prefix}:batch_retry") { ReminderFlow.new(now: TEST_NOW).run_daily_batch(CLINIC, TEST_NOW.to_date) }
          assert_equal identities, [Visit.for_clinic(CLINIC).order(:id).ids, Message.where(clinic_id: CLINIC).order(:id).ids]
          receipt = Message.find_by!(clinic_id: CLINIC, patient_id: PATIENT)
          key = "workload-#{history}-#{relevant}"
          assert_equal "Appointment confirmed.", measure("#{prefix}:reply") {
            ReceiveReply.new(now: TEST_NOW).reply_to_receipt(receipt: receipt, text: "YES", request_key: key)
          }
          assert_equal "Appointment confirmed.", measure("#{prefix}:reply_retry") {
            ReceiveReply.new(now: TEST_NOW).reply_to_receipt(receipt: receipt, text: "YES", request_key: key)
          }
          assert_equal 1, ActivityEvent.where(request_key: key).count
          assert Visit.current.find_by!(appointment_id: APPOINTMENT).confirmed_at

          get "/"
          header "X-CSRF-Token", last_response.body[/name="csrf-token" content="([^"]+)"/, 1]
          header "Content-Type", "application/json"
          post "/api/enter", JSON.generate(workspace: "desk", clinic: CLINIC, staff: CLINIC)
          assert last_response.ok?, last_response.body
          measure("#{prefix}:history_request") {
            get "/api/patient-details/#{PATIENT}/history", section: "appointments"
          }
          assert last_response.ok?, last_response.body
          rows = JSON.parse(last_response.body).fetch("rows")
          assert_equal [APPOINTMENT], rows.pluck("appointment_id")
          measure("#{prefix}:response_bytes=#{last_response.body.bytesize}") { rows }

          post "/api/enter", JSON.generate(workspace: "apex")
          assert last_response.ok?, last_response.body
          measure("#{prefix}:operations_request") { get "/api/operations", month: "2026-11" }
          assert last_response.ok?, last_response.body
          result = JSON.parse(last_response.body).fetch("rows").find { |row| row.values_at("clinic_id", "outcome_month") == [CLINIC, "2026-11"] }
          assert_equal relevant, Message.where(clinic_id: CLINIC, patient_id: PATIENT...(PATIENT + relevant)).count
          assert_equal 1, result.fetch("patient_confirmed") if result.fetch("total") > 0

          old_visit = Visit.current.find_by!(appointment_id: APPOINTMENT)
          old_messages = Message.where(clinic_id: CLINIC).order(:id).ids
          PG.connect(ENV.fetch("PMS_ADMIN_URL")) do |source|
            source.exec_params("UPDATE pms.patients SET wireless_phone='(512) 300-0000' WHERE id=$1", [PATIENT])
            source.exec_params("UPDATE pms.appointments SET start_at=start_at+interval '1 hour' WHERE id=$1", [APPOINTMENT])
          end
          measure("#{prefix}:changed_source_tick") { ReminderRunner.tick }
          assert_equal "+15123000000", Patient.find(PATIENT).comparison_phone
          assert_equal "(512) 300-0000", Patient.find(PATIENT).wireless_phone
          refute old_visit.reload.current
          replacement = Visit.current.find_by!(appointment_id: APPOINTMENT)
          refute_equal old_visit.id, replacement.id
          assert_nil replacement.confirmed_at
          assert_equal old_messages, Message.where(clinic_id: CLINIC).order(:id).ids
          measure("#{prefix}:unchanged_tick") { ReminderRunner.tick }
          assert_equal replacement.id, Visit.current.find_by!(appointment_id: APPOINTMENT).id
          assert_equal old_messages, Message.where(clinic_id: CLINIC).order(:id).ids
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  def populate_unrelated_history(relevant, count)
    appointments = Appointment.for_clinic(CLINIC).where(status: "complete").order(:id).to_a
    visits = appointments.map do |appointment|
      { appointment_id: appointment.id, patient_id: appointment.patient_id, clinic_id: CLINIC,
        start_at: appointment.start_at, revision: appointment.confirmation_revision, current: false }
    end
    Visit.insert_all!(visits, returning: false)
    saved = Visit.for_clinic(CLINIC).where(current: false).order(:id).to_a
    AppointmentHistory.record_visits(saved)
    FollowUpCase.insert_all!(saved.map do |visit|
      { patient_id: visit.patient_id, clinic_id: CLINIC, state: "resolved", due_at: TEST_NOW - 25.days, updated_at: TEST_NOW - 24.days }
    end, returning: false)
    cases = FollowUpCase.for_clinic(CLINIC).pluck(:patient_id, :id).to_h
    rows = saved.map do |visit|
      { case_id: cases.fetch(visit.patient_id), visit_id: visit.id, code: "patient", reason: "Handled historical reply",
        created_at: TEST_NOW - 25.days, resolved_at: TEST_NOW - 24.days }
    end
    FollowUpIssue.insert_all!(rows, returning: false)
    FollowUpIssue.index_visits(FollowUpIssue.where(case_id: cases.values))
    messages = saved.map do |visit|
      { patient_id: visit.patient_id, clinic_id: CLINIC, clinic_name: "Workload clinic", sender: "+15125550198",
        channel: "SMS", destination: "+1512#{3_000_000 + visit.patient_id - PATIENT}",
        body: "Historical reminder", token: "history-#{visit.id}", status: "sent", created_at: TEST_NOW - 25.days, recipient_id: visit.patient_id }
    end
    ids = Message.insert_all!(messages, returning: %w[id patient_id]).to_h { |row| [row.fetch("patient_id"), row.fetch("id")] }
    MessageItem.insert_all!(saved.map { |visit| { visit_id: visit.id, message_id: ids.fetch(visit.patient_id), purpose: "initial" } }, returning: false)
    ActivityEvent.insert_all!(saved.map do |visit|
      { visit_id: visit.id, message_id: ids.fetch(visit.patient_id), actor: "Fake SMS", kind: "sent",
        body: "initial", created_at: TEST_NOW - 25.days }
    end, returning: false)
    # This is retained history. Give PostgreSQL the statistics it would already have for aged rows.
    %w[desk.visits desk.messages desk.message_items desk.events desk.issues desk.issue_candidates desk.appointment_histories].each do |table|
      ApplicationRecord.connection.execute("ANALYZE #{table}")
    end
    assert_equal count, FollowUpIssue.where(case_id: cases.values).count
    assert_equal count, Message.where(patient_id: saved.map(&:patient_id), clinic_id: CLINIC).count
  end
end

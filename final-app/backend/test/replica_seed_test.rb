require_relative "test_helper"
require_relative "../db/replica/seeds"

class ReplicaSeedTest < Minitest::Test
  def test_setup_normalizes_only_legacy_demo_names
    ReplicaSeed::Record.transaction do
      repeated = ReplicaSeed::Patient.find(103)
      unnumbered = ReplicaSeed::Patient.find(104)
      unmatched = ReplicaSeed::Patient.find(106)
      repeated.update!(first_name: "Demo Patient", last_name: "Patient #103")
      unnumbered.update!(first_name: "Demo", last_name: "Patient")
      unmatched.update!(first_name: "Demo Patient", last_name: "Patient #103")

      assert_equal 2, ReplicaSeed.normalize_legacy_patient_names
      assert_equal ["Demo Patient", "103"], repeated.reload.attributes.values_at("first_name", "last_name")
      assert_equal ["Demo Patient", "104"], unnumbered.reload.attributes.values_at("first_name", "last_name")
      assert_equal "Patient #103", unmatched.reload.last_name
      assert_equal 0, ReplicaSeed.normalize_legacy_patient_names
      raise ActiveRecord::Rollback
    end
  end

  def test_baseline_backfill_adds_september_once_without_changing_existing_appointments
    ReplicaSeed::Record.transaction do
      existing = ReplicaSeed::Appointment.order(:id).pluck(:id, :status)
      2.times { ReplicaSeed.backfill_history(first_day: Date.new(2026, 9, 1)) }

      baseline = ReplicaSeed::Appointment.where(start_at: Date.new(2026, 9, 1)...Date.new(2026, 10, 1))
      assert_equal({ 1 => 130, 5 => 130 }, baseline.group(:clinic_id).count)
      assert_equal existing, ReplicaSeed::Appointment.where.not(id: baseline.select(:id)).order(:id).pluck(:id, :status)
      raise ActiveRecord::Rollback
    end
  end

  def test_relative_seed_handles_weekends_month_boundaries_and_other_years
    url = ENV.fetch("PMS_ADMIN_URL")
    abort "Use a disposable PMS database ending in _test." unless URI(url).path.end_with?("_test")
    ReplicaSeed::Record.establish_connection(url)

    ["2027-02-28T23:45:00-06:00", "2030-03-10T08:00:00-05:00", "2027-05-31T14:00:00-05:00"].each do |seed_at|
      ReplicaSeed::Record.transaction do
        ReplicaSeed::Appointment.delete_all
        ReplicaSeed::Patient.delete_all
        ReplicaSeed::Clinic.delete_all
        now = Time.iso8601(seed_at)
        ReplicaSeed.load(now: now)
        existing = ReplicaSeed::Appointment.order(:id).pluck(:id, :status)
        2.times { ReplicaSeed.seed_phoenix_comparison_month(now: now) }
        month = now.in_time_zone("America/Phoenix").to_date.beginning_of_month
        added = ReplicaSeed::Appointment.where.not(id: existing.map(&:first))
        assert_equal (month...month.next_month).count { |day| !day.sunday? } * 5, added.count, seed_at
        assert_equal [5], added.distinct.pluck(:clinic_id), seed_at
        assert_equal existing, ReplicaSeed::Appointment.where.not(id: added.select(:id)).order(:id).pluck(:id, :status), seed_at
        patients = ReplicaSeed::Patient.order(:id).to_a
        assert_equal (1..patients.length).to_a, patients.map(&:id), seed_at
        assert patients.all? { |patient| patient.first_name == "Demo Patient" && patient.last_name == patient.id.to_s }, seed_at

        appointments = ReplicaSeed::Appointment.all.to_a
        appointments.group_by { |a| [a.clinic_id, a.start_at.to_date] }.each do |(_clinic, day), visits|
          assert_equal 5, visits.length, seed_at
          refute day.sunday?, seed_at
        end
        assert appointments.group_by(&:patient_id).values.all? { |visits| visits.length <= 6 }, seed_at
        local_now = now.in_time_zone("America/Chicago")
        wall_now = Time.utc(local_now.year, local_now.month, local_now.day, local_now.hour, local_now.min)
        upcoming_ids = [102, 103, 104, 106, 107, 110, 123, 22, 26, 27]
        assert_equal 10, appointments.count { |a| upcoming_ids.include?(a.id) && a.status == "scheduled" && a.start_at > wall_now }, seed_at
        assert_equal "complete", ReplicaSeed::Appointment.find(109).status, seed_at
        assert ReplicaSeed::Patient.where(id: [161, 167, 168]).all? { |p| p.birthdate > local_now.to_date.years_ago(18) }, seed_at
        raise ActiveRecord::Rollback
      end
    end
  end
end

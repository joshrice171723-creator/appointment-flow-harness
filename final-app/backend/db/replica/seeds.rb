require "digest"
require "zlib"

# These writable models exist only in the setup process, never in the running app.
class ReplicaSeed
  class Record < ActiveRecord::Base
    self.abstract_class = true
  end
  class Clinic < Record
    self.table_name = "pms.clinics"
  end
  class Patient < Record
    self.table_name = "pms.patients"
  end
  class Appointment < Record
    self.table_name = "pms.appointments"
  end

  WALKTHROUGH = {
    [-1, 2] => [109, 109], [-1, 5] => [21, 155],
    [0, 2] => [104, 104], [0, 3] => [103, 103], [0, 5] => [123, 111],
    [1, 2] => [102, 102], [1, 4] => [107, 107], [2, 4] => [106, 106],
    [6, 3] => [110, 110], [2, 2] => [22, 161], [2, 3] => [23, 162],
    [3, 4] => [24, 163], [4, 2] => [25, 165],
    [3, 2] => [26, 167], [3, 3] => [27, 168]
  }.freeze
  HOURS = [9, 11, 12, 15, 17].freeze

  def self.load(now:)
    new(now).load
  end

  def self.seed_phoenix_comparison_month(now:)
    new(now).seed_phoenix_comparison_month
  end

  def self.patient_name(id)
    { first_name: "Demo Patient", last_name: id.to_s }
  end

  def self.normalize_legacy_patient_names
    repeated_name = Patient.where(first_name: "Demo Patient")
      .where("last_name = 'Patient #' || id::text")
    unnumbered_name = Patient.where(first_name: "Demo", last_name: "Patient")

    repeated_name.or(unnumbered_name)
      .update_all(first_name: "Demo Patient", last_name: Arel.sql("id::text"))
  end

  def self.backfill_history(first_day:)
    Record.transaction do
      patient_id = Patient.maximum(:id).to_i
      appointment_id = Appointment.maximum(:id).to_i
      Clinic.find_each do |clinic|
        first_existing = Appointment.where(clinic_id: clinic.id).minimum(:start_at)&.to_date
        next unless first_existing && first_day < first_existing

        visits = (first_day...first_existing).reject(&:sunday?).flat_map do |day|
          HOURS.map.with_index do |hour, slot|
            patient_id += 1
            appointment_id += 1
            start_at = Time.utc(day.year, day.month, day.day, hour)
            rank = Zlib.crc32("outcome-#{clinic.id}-#{day}-#{slot}") % 100
            status = case rank
                     when 0...7 then "broken"
                     when 7...14 then "unscheduled"
                     else "complete"
                     end
            { id: appointment_id, patient_id: patient_id, clinic_id: clinic.id, provider_name: "Dr. Jordan Patel",
              start_at: start_at, length_minutes: 30, status: status, updated_at: start_at + 1.hour }
          end
        end
        patients = visits.map do |visit|
          id = visit.fetch(:patient_id)
          number = visit.fetch(:start_at).to_date.jd % 1500 * HOURS.length + id % 10
          { id: id, **patient_name(id), birthdate: Date.new(1990, 1, 1),
            wireless_phone: format("(737) 555-%04d", 2000 + number),
            email: "patient.#{id}@example.test", preferred_language: "en" }
        end
        Patient.insert_all!(patients)
        Appointment.insert_all!(visits)
      end
    end
  end

  def initialize(now)
    @now = now.in_time_zone("America/Chicago")
    @outreach_day = @now.to_date + (@now.hour >= 11 ? 1 : 0)
    @outreach_day += 1 if @outreach_day.sunday?
  end

  def load
    Record.transaction do
      Clinic.create!(id: 1, name: "Austin", address_line: "101 Cedar Lane", city: "Austin", state: "TX", phone: "(512) 555-0100")
      Clinic.create!(id: 5, name: "Phoenix", address_line: "105 Cedar Lane", city: "Phoenix", state: "AZ", phone: "(602) 555-0100")
      appointments = build_schedule
      create_patients(appointments)
      assign_past_outcomes(appointments)
      appointments.each { |appointment| appointment.delete(:outcome_key) }
      Appointment.insert_all!(appointments)
    end
  end

  def seed_phoenix_comparison_month
    phoenix = Clinic.find_by(id: 5, name: "Phoenix")
    return unless phoenix

    local_now = @now.in_time_zone("America/Phoenix")
    first_day = local_now.to_date.beginning_of_month
    phoenix.with_lock do
      next if Appointment.where(clinic_id: phoenix.id, start_at: first_day...first_day.next_month).exists?

      patient_id = Patient.maximum(:id).to_i
      appointment_id = Appointment.maximum(:id).to_i
      appointments = (first_day...first_day.next_month).reject(&:sunday?).flat_map do |day|
        HOURS.map do |hour|
          patient_id += 1
          appointment_id += 1
          start_at = Time.utc(day.year, day.month, day.day, hour)
          { id: appointment_id, patient_id: patient_id, clinic_id: phoenix.id, provider_name: "Dr. Jordan Patel",
            start_at: start_at, outcome_key: [phoenix.id, day, hour], length_minutes: 30, procedure_note: "Synthetic demo",
            status: "scheduled", updated_at: start_at - 14.days }
        end
      end
      patients = appointments.map do |appointment|
        id = appointment.fetch(:patient_id)
        { id: id, **self.class.patient_name(id), birthdate: Date.new(1990, 1, 1),
          email: "patient.#{id}@example.test", preferred_language: "en" }
      end
      assign_past_outcomes(appointments, local_now: local_now)
      appointments.each { |appointment| appointment.delete(:outcome_key) }
      Patient.insert_all!(patients)
      Appointment.insert_all!(appointments)
    end
  end

  private

  def open_day(offset)
    day = @outreach_day
    offset.abs.times do
      day += offset.negative? ? -1 : 1
      day += offset.negative? ? -1 : 1 if day.sunday?
    end
    day
  end

  def build_schedule
    examples = WALKTHROUGH.to_h { |(offset, slot), ids| [[open_day(offset), slot], ids] }
    first_day = @now.to_date.prev_month.beginning_of_month
    appointments = []
    reserved_ids = WALKTHROUGH.values.map(&:first)
    next_id = 1
    [1, 5].each do |clinic_id|
      last_day = clinic_id == 1 ? [@now.to_date.end_of_month, @outreach_day + 10].max : first_day.end_of_month
      days = (first_day..last_day).reject(&:sunday?)
      number = 0
      days.group_by(&:beginning_of_week).each do |week, week_days|
        week_days.each_with_index do |day, day_index|
          HOURS.each_with_index do |hour, slot_index|
            number += 1
            slot = slot_index + 1
            ids = clinic_id == 1 ? examples[[day, slot]] : nil
            repeats = slot == 1 && (week_days.length >= 5 ? [0, 2, 4].include?(day_index) : day_index < 3)
            patient_key = repeats ? [clinic_id, week] : [clinic_id, day, slot]
            unless ids
              next_id += 1 while reserved_ids.include?(next_id)
              appointment_id = next_id
              next_id += 1
            end
            start_at = Time.utc(day.year, day.month, day.day, hour)
            appointments << {
              id: ids ? ids.first : appointment_id,
              outcome_key: ids ? ids.last : [clinic_id, number], patient_id: ids ? ids.last : patient_key,
              clinic_id: clinic_id, provider_name: slot.even? ? "Dr. Avery Lee" : "Dr. Jordan Patel",
              start_at: start_at, length_minutes: 30, procedure_note: "Synthetic demo",
              status: "scheduled", updated_at: start_at - 14.days
            }
          end
        end
      end
    end
    appointments
  end

  def create_patients(appointments)
    reserved = WALKTHROUGH.values.map(&:last).uniq + [190, 191]
    next_id = 1
    generated = {}
    appointments.each do |appointment|
      key = appointment[:patient_id]
      next if key.is_a?(Integer)

      generated[key] ||= begin
        next_id += 1 while reserved.include?(next_id)
        next_id.tap { next_id += 1 }
      end
      appointment[:patient_id] = generated.fetch(key)
    end
    patients = appointments.map { |a| [a[:patient_id], a[:clinic_id]] }.uniq.to_h
    [190, 191].each { |id| patients[id] = 1 }
    rows = patients.sort.map.with_index do |(id, clinic_id), index|
      {
        id: id, **self.class.patient_name(id), birthdate: Date.new(1990, 1, 1),
        wireless_phone: format("(%s) 555-%04d", clinic_id == 1 ? "737" : "602", 1000 + index),
        email: "patient.#{id}@example.test", preferred_language: "en", guarantor_id: nil
      }
    end
    contacts = {
      102 => ["(512) 555-0102", "maya.102@example.test"], 104 => [nil, nil],
      103 => ["Old number: 512-555-0103", "noah.103@example.test"],
      106 => ["(512) 555-0106", "alex.106@example.test"], 107 => ["5125550106", "jamie.107@example.test"],
      109 => ["512 555–0109", "grace.109@example.test"], 110 => ["(512) 555-0110", "robin.110@example.test"],
      111 => ["512.555.0111", "kelly.111@example.test"], 190 => ["1 512 555 0191", "morgan.brooks@example.test"],
      191 => ["Ask for new number", " Casey.Reed@EXAMPLE.TEST "],
      162 => ["210-555-0153 x204", " Pat.162+Visits@EXAMPLE.TEST "],
      163 => ["210-555-0154 or 512-555-0199", "pat..163@example.test"],
      165 => ["LQ nine five - 32", "first@example.test; second@example.test"]
    }
    rows.each do |row|
      row[:wireless_phone], row[:email] = contacts.fetch(row[:id]) if contacts.key?(row[:id])
      row[:preferred_language] = "es-MX" if row[:id] == 103
    end
    Patient.insert_all!(rows)
    {161 => [12, 190], 167 => [10, 191], 168 => [11, 190]}.each do |id, (age, guardian)|
      Patient.find(id).update!(birthdate: @now.to_date.years_ago(age), guarantor_id: guardian)
    end
    Patient.find(167).update!(wireless_phone: nil, email: nil)
  end

  def assign_past_outcomes(appointments, local_now: @now)
    wall_now = Time.utc(local_now.year, local_now.month, local_now.day, local_now.hour, local_now.min, local_now.sec)
    appointments.group_by { |a| [a[:clinic_id], a[:start_at].strftime('%Y-%m'), a[:start_at] < wall_now] }.each_value do |group|
      group.sort_by { |a| Digest::MD5.hexdigest("attendance-#{a[:outcome_key]}") }.each_with_index do |appointment, index|
        local_start = appointment[:start_at]
        next if local_start + 35.minutes >= wall_now

        rank = group.length == 1 ? 0 : index.fdiv(group.length - 1)
        rescheduled_limit, canceled_limit = appointment[:clinic_id] == 1 ? [0.05, 0.10] : [0.15, 0.28]
        appointment[:status] = if appointment[:id] == 109
          "complete"
        elsif rank < rescheduled_limit
          "broken"
        elsif rank < canceled_limit
          "unscheduled"
        else
          "complete"
        end
        appointment[:updated_at] = [local_start + 1.hour, wall_now].min
      end
    end
  end
end

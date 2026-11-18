class ContactPolicy
  SMS_CHANNEL = "SMS"
  EMAIL_CHANNEL = "Email"
  ADULT_AGE_YEARS = 18
  MAX_EMAIL_BYTES = 254
  MAX_EMAIL_LOCAL_BYTES = 64
  PHONE_SEPARATOR = /[[:blank:]]*(?:[.\-\u2010-\u2013][[:blank:]]*)?/
  US_PHONE_NUMBER = /
    \A [[:blank:]]*
    (?: \+?1 #{PHONE_SEPARATOR} )?
    (?: \([2-9][0-9]{2}\) | [2-9][0-9]{2} ) #{PHONE_SEPARATOR}
    [2-9][0-9]{2} #{PHONE_SEPARATOR} [0-9]{4}
    [[:blank:]]* \z
  /x

  def initialize(now)
    @now = now
  end

  attr_reader :now

  def phone(value)
    number = value.to_s
    return unless US_PHONE_NUMBER.match?(number)

    "+1#{number.delete("^0-9").delete_prefix("1")}"
  end

  def address(value)
    email = value.to_s.gsub(/\A[[:blank:]]+|[[:blank:]]+\z/, "")
    return unless email.bytesize <= MAX_EMAIL_BYTES && email.match?(URI::MailTo::EMAIL_REGEXP)

    local, domain = email.split("@", 2)
    return if local.bytesize > MAX_EMAIL_LOCAL_BYTES || local.start_with?(".") || local.end_with?(".") || local.include?("..")
    return unless domain.include?(".")

    "#{local}@#{domain.downcase}"
  end

  # Only the selected adult's normalized channels leave this policy.
  Recipient = Data.define(:id, :name, :phone, :email, :language, :phone_on_file)

  def recipient(patient:, permission:, timezone:)
    zone = Time.find_zone(timezone)
    return unless patient && zone && !patient.contact_details_conflicted?

    today = now.in_time_zone(zone).to_date
    birthdate = patient.effective_detail("birthdate")
    return unless birthdate && birthdate <= today

    adult_cutoff = today << (ADULT_AGE_YEARS * 12)
    adult = if birthdate <= adult_cutoff
      patient
    else
      authorized_guarantor(patient, permission, adult_cutoff)
    end
    return unless adult && !adult.contact_details_conflicted?

    phone_on_file = adult.effective_detail("wireless_phone")
    Recipient.new(
      id: adult.id,
      name: (adult.display_name if adult.id != patient.id),
      phone: phone(phone_on_file),
      email: address(adult.effective_detail("email")),
      language: adult.effective_detail("preferred_language"),
      phone_on_file: phone_on_file
    )
  end

  HOLD_MESSAGES = {
    patient_mapping: "Patient mapping needs review.",
    appointment_time: "Appointment time needs review.",
    missing_age: "Verify the patient's age and authorized contact.",
    conflicting_details: "Review conflicting PMS and locally verified patient details before sending reminders.",
    authorized_adult: "Verify an authorized adult before contacting this patient.",
    no_contact: "No valid phone or email on file.",
    language: "Arrange a conversation in the patient's preferred language."
  }.freeze
  ISSUE_REASONS = {
    missing_phone: "No phone number on file and no usable email.",
    invalid_phone: "Invalid phone number on file and no usable email.",
    permission: "No permitted SMS or email channel. Check permissions and opt-outs.",
    opt_out: "The recipient opted out of SMS and has no permitted email channel."
  }.freeze
  CHANNEL_RESTORED = "A permitted reminder channel is available again.".freeze

  def for_visit(visit)
    recipient(patient: visit.patient, permission: visit.contact_permission, timezone: visit.timezone)
  end

  def hold_code(visit, contact: for_visit(visit))
    return :patient_mapping unless visit.patient
    return :appointment_time if !visit.starts_at_utc || visit.start_at.sunday?
    return :conflicting_details if verification_conflict?(visit)
    return :missing_age unless visit.patient.effective_detail("birthdate")
    return :authorized_adult unless contact
    return :no_contact unless contact.phone || contact.email

    :language unless MessageTemplates.new.message_language(contact.language)
  end

  def hold(visit, **options)
    HOLD_MESSAGES[hold_code(visit, **options)]
  end

  def destinations(visit, contact:, opt_outs:)
    channels = {}
    if contact.phone && visit.sms_permitted? && !opt_outs.include?(contact.phone)
      channels[SMS_CHANNEL] = contact.phone
    end
    channels[EMAIL_CHANNEL] = contact.email if contact.email && visit.email_permitted?
    channels
  end

  Decision = Data.define(:recipient, :destinations, :reason_code, :reason)

  def decision(visit, opt_outs:)
    contact = for_visit(visit)
    hold = hold_code(visit, contact: contact)
    channels = hold ? {} : destinations(visit, contact: contact, opt_outs: opt_outs)
    reason_code = delivery_blocker(visit, contact: contact, hold: hold, channels: channels, opt_outs: opt_outs)
    Decision.new(recipient: contact, destinations: channels, reason_code: reason_code,
      reason: ISSUE_REASONS[reason_code] || HOLD_MESSAGES[reason_code])
  end

  def verification_conflict?(visit)
    patient = visit.patient
    return false unless patient
    return true if patient.contact_details_conflicted?
    return false unless Time.find_zone(visit.timezone)

    birthdate = patient.effective_detail("birthdate")
    cutoff = now.in_time_zone(visit.timezone).to_date << (ADULT_AGE_YEARS * 12)
    return false unless birthdate && birthdate > cutoff

    guardian = visit.contact_permission&.authorized_guarantor
    guardian && guardian.id == patient.guarantor_id && guardian.contact_details_conflicted?
  end

  private

  def delivery_blocker(visit, contact:, hold:, channels:, opt_outs:)
    return contact.phone_on_file.blank? ? :missing_phone : :invalid_phone if hold == :no_contact
    return hold if hold
    return if channels.any?

    visit.sms_permitted? && opt_outs.include?(contact.phone) ? :opt_out : :permission
  end

  def authorized_guarantor(patient, permission, adult_cutoff)
    guardian = permission&.authorized_guarantor
    return unless guardian && guardian.id == patient.guarantor_id
    return if guardian.id == patient.id
    birthdate = guardian.effective_detail("birthdate")
    return unless birthdate && birthdate <= adult_cutoff

    guardian
  end
end

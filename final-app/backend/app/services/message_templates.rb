class MessageTemplates
  SMS_OPT_OUT = " Reply STOP to stop texts."

  def english?(language)
    value = language.to_s.strip.downcase.tr("_", "-")
    value.empty? || value == "english" || value.match?(/\Aen(?:-[a-z]{2})?\z/)
  end

  def message_language(language)
    return :en if english?(language)
    value = language.to_s.strip.downcase.tr("_", "-")
    :es if %w[spanish español].include?(value) || value.match?(/\Aes(?:-[a-z]{2})?\z/)
  end

  def message_body(visit, channel, purposes, language:)
    confirmed_reminder = purposes.include?("courtesy") && visit.confirmed_at
    if message_language(language) == :es
      start = visit.start_at.strftime("%Y-%m-%d a las %H:%M")
      body = "#{confirmed_reminder ? 'Recordatorio de cita confirmada' : 'Cita'}: #{start} (hora local), #{visit.clinic.name}."
      body += confirmed_reminder ? " No necesita responder." : " Responda SÍ para confirmar o NO si necesita ayuda."
      body += " Responda STOP para dejar de recibir mensajes de texto." if channel == "SMS"
    else
      start = visit.start_at.strftime("%a, %b %-d, %Y at %-I:%M %p")
      body = "#{confirmed_reminder ? 'Confirmed appointment reminder' : 'Appointment'}: #{start} local time, #{visit.clinic.name}."
      body += confirmed_reminder ? " No response needed." : " Reply YES to confirm or NO for help."
      body += SMS_OPT_OUT if channel == "SMS"
    end
    body
  end

end

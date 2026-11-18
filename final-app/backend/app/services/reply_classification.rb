module ReplyClassification
  AFFIRMATIVE = /\A(?:yes|yeah|ya|sí|si)[!.]*\z/i
  AFFIRMATIVE_LEAD = /\A(?:yes|yeah|ya|sí|si)(?:[[:space:][:punct:]]|\z)/i
  DECLINE = /\Ano(?:,\s+i (?:can't|cannot) make it)?[!.]*\z/i

  def self.call(text)
    text = text.to_s.strip
    return :affirmative if AFFIRMATIVE.match?(text)
    return :decline if DECLINE.match?(text)

    :review
  end

  def self.affirmative_lead?(text)
    AFFIRMATIVE_LEAD.match?(text.to_s.strip)
  end
end

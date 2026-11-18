# Serialize stored wall-clock fields without a display-zone conversion.
module PmsTimestamp
  def self.text(value, separator: "T")
    time = value.getutc
    year = time.year.negative? ? "-#{format('%04d', -time.year)}" : format("%04d", time.year)
    result = format("%s-%02d-%02d%s%02d:%02d:%02d", year, time.month, time.day,
      separator, time.hour, time.min, time.sec)
    time.usec.zero? ? result : result + format(".%06d", time.usec)
  end
end

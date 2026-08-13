class Break < ApplicationRecord
  belongs_to :time_clock
  VALID_BREAK_TYPES = [
    "Meal Break - 40 Minutes",
    "Second Break - 30 minutes",
    "Meeting",
    "Extra Break",
    "Downtime",
    "Cigarette Break",
    "Chai/Coffee Break",
    "Washroom Break",
    "Namaz Break",
  ]

  MEETING_BREAK_TYPE = "Meeting"

  validates :break_type, inclusion: { in: VALID_BREAK_TYPES }

  # Meetings are paid time, so they are never subtracted from the worked total.
  # Compared case/whitespace insensitively - some rows were stored with stray
  # casing or a trailing space.
  def meeting?
    break_type.to_s.strip.casecmp(MEETING_BREAK_TYPE).zero?
  end

  def duration
    return 0 if break_in.blank? || break_out.blank?
    (break_out - break_in)
  end

  def formatted_duration(seconds)
    return "N/A" if seconds.blank? || seconds <= 0
  
    seconds = seconds.to_i  # ensure integer
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    "#{hours}h #{minutes}m"
  end
end

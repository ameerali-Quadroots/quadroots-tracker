class Break < ApplicationRecord
  belongs_to :time_clock

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

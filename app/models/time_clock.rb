class TimeClock < ApplicationRecord
  belongs_to :employee, class_name: "User", foreign_key: "user_id"
  has_many :breaks, dependent: :destroy
  has_many :edit_requests

  accepts_nested_attributes_for :breaks, allow_destroy: true

  # def break_duration
  #   breaks.sum do |b|
  #     if b.break_in.present? && b.break_out.present?
  #       (b.break_out - b.break_in) / 60
  #     else
  #       0
  #     end
  #   end.round
  # end

  def calculate_total_duration
  return if clock_in.blank? || clock_out.blank?

  worked_seconds = (clock_out - clock_in).to_i - total_break_seconds
  self.total_duration = [worked_seconds, 0].max
end


def duration_in_hours
  return nil if clock_out.blank? || clock_in.blank?

  total = (clock_out - clock_in) - breaks.where.not(break_type: "meeting").sum(&:duration)
  (total / 3600).round(2)
end

  def formatted_duration(seconds)
    return "N/A" if seconds.blank? || seconds <= 0
  
    seconds = seconds.to_i  # ensure integer
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    "#{hours}h #{minutes}m"
  end

  def on_break?
    breaks.any? && breaks.last.break_out.blank?
  end


  def total_break_seconds
  return 0 if breaks.blank?

  # Only subtract breaks that are NOT meetings
  breaks.where.not(break_type: "meeting").sum do |b|
    if b.break_out.present?
      (b.break_out - b.break_in).to_i
    else
      0
    end
  end
end




  def formatted_break_duration
    seconds = total_break_seconds
    return "N/A" if seconds.blank? || seconds <= 0
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    "#{hours}h #{minutes}m"
  end

  def live_working_duration
  return total_duration if clock_out.present?

  now = Time.zone.now

  break_seconds = breaks.where.not(break_type: "meeting").sum do |br|
    (br.break_out || now) - br.break_in
  end

  (now - clock_in - break_seconds).to_i
end

def calculate_downtime(now = Time.current)
  downtime_seconds = 0

  if respond_to?(:breaks) && breaks.any?
    downtime_breaks = breaks.where(break_type: "Downtime")
    downtime_seconds = downtime_breaks.sum do |br|
      (br.break_out || now) - br.break_in
    end
  end

  # convert to hours and minutes
  hours   = downtime_seconds.to_i / 3600
  minutes = (downtime_seconds.to_i % 3600) / 60

  format("%02d:%02d", hours, minutes) # => "HH:MM"
end



  def calculate_total_duration
    return if clock_in.blank? || clock_out.blank?

    worked_seconds = (clock_out - clock_in).to_i - total_break_seconds
    self.total_duration = [worked_seconds, 0].max
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      user_id
      clock_in
      clock_out
      total_duration
      status
      current_state
      created_at
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[employee breaks]
  end

end

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

  # Only subtract breaks that are NOT meetings.
  # Iterate the loaded association (no extra query) instead of breaks.where(...)
  breaks.sum do |b|
    next 0 if b.break_type.blank? || b.break_type == "meeting"
    next 0 if b.break_out.blank?

    (b.break_out - b.break_in).to_i
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

  break_seconds = breaks.sum do |br|
    next 0 if br.break_type.blank? || br.break_type == "meeting"

    (br.break_out || now) - br.break_in
  end

  (now - clock_in - break_seconds).to_i
end

def calculate_downtime(now = Time.current)
  downtime_seconds = 0

  if respond_to?(:breaks) && breaks.any?
    downtime_seconds = breaks.sum do |br|
      next 0 unless br.break_type == "Downtime"

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

  # The datetime the employee's shift was supposed to start for this record,
  # based on the employee's configured shift_time (defaults to 18:00).
  def shift_start
    return nil if clock_in.blank?

    st = employee&.shift_time || Time.zone.parse("18:00")
    candidate = clock_in.change(hour: st.hour, min: st.min, sec: 0)
    # Overnight shift: clocked in in the early morning belongs to the previous day's shift
    candidate -= 1.day if clock_in < candidate - 1.hour
    candidate
  end

  # How many whole minutes late the employee clocked in (0 if on time / early).
  def late_minutes
    return 0 if clock_in.blank? || shift_start.blank?

    minutes = ((clock_in - shift_start) / 60).to_i
    minutes.positive? ? minutes : 0
  end

  # Completed break seconds grouped by break_type, e.g. { "Namaz Break" => 600 }
  def break_seconds_by_type
    breaks.each_with_object(Hash.new(0)) do |b, acc|
      next if b.break_in.blank? || b.break_out.blank?

      acc[b.break_type] += (b.break_out - b.break_in).to_i
    end
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

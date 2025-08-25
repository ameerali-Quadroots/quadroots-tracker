class TimeClock < ApplicationRecord
  belongs_to :user
  has_many :breaks, dependent: :destroy

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
    return nil unless clock_in && clock_out

    worked = clock_out - clock_in
    break_seconds = breaks.sum { |br| (br.break_out || clock_out) - br.break_in }
    (worked - break_seconds).to_i
  end

  def duration_in_hours
    return nil if clock_out.blank? || clock_in.blank?
    total = (clock_out - clock_in) - breaks.sum(&:duration)
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

    breaks.sum do |b|
      if b.break_out.present?
        (b.break_out - b.break_in).to_i
      else
        0
      end
    end
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
      created_at
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user breaks]
  end

end

class Break < ApplicationRecord
  belongs_to :time_clock

  def duration
    return 0 if break_in.blank? || break_out.blank?
    (break_out - break_in)
  end
end

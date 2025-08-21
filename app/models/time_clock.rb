class TimeClock < ApplicationRecord
  belongs_to :user


  def duration
    return nil if clock_out.blank? || clock_in.blank?
    ((clock_out - clock_in) / 60).round # duration in minutes
  end

  def duration_in_hours
    return nil if clock_out.blank? || clock_in.blank?
    ((clock_out - clock_in) / 3600).round(2) # duration in hours
  end


  def self.ransackable_attributes(auth_object = nil)
    # List the attributes you want to be searchable here
    ["clock_in", "clock_out", "created_at", "updated_at", "user_id", "hours_worked"]
  end
  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
end

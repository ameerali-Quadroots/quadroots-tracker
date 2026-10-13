# Each time clock now remembers when its shift was due to start. Until now that
# was worked out from the employee's *current* shift_time, so changing a shift
# time (e.g. 6 PM to 8 PM for winter) would have moved every past record: a
# 6:05 PM clock-in reads as "two hours early" against 8 PM and lands on the
# previous day. Existing rows are filled in from the shift times in force today.
class AddShiftStartAtToTimeClocks < ActiveRecord::Migration[7.1]
  def up
    add_column :time_clocks, :shift_start_at, :datetime

    TimeClock.reset_column_information
    TimeClock.where.not(clock_in: nil).includes(:employee).find_each do |time_clock|
      time_clock.update_columns(shift_start_at: time_clock.shift_start_for(time_clock.employee&.shift_time))
    end
  end

  def down
    remove_column :time_clocks, :shift_start_at
  end
end

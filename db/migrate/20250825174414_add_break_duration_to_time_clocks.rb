class AddBreakDurationToTimeClocks < ActiveRecord::Migration[7.1]
  def change
    add_column :time_clocks, :break_duration, :integer
  end
end

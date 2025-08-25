class AddTotalDurationToTimeClocks < ActiveRecord::Migration[7.1]
  def change
    add_column :time_clocks, :total_duration, :integer
  end
end

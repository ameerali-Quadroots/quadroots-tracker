class AddShiftTimeToUsers < ActiveRecord::Migration[6.1]  # or [7.0], depending on your version
  def change
    add_column :users, :shift_time, :time, default: "2000-01-01 18:00:00"
  end
end

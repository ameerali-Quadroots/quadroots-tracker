class AddStatusToTimeClocks < ActiveRecord::Migration[7.1]
  def change
    add_column :time_clocks, :status, :string
  end
end

class AddStateToTimeClocks < ActiveRecord::Migration[7.1]
  def change
    add_column :time_clocks, :current_state, :string
  end
end

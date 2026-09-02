class AddParentAndPositionToTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :tasks, :parent, foreign_key: { to_table: :tasks }, null: true
    add_column :tasks, :position, :integer, null: false, default: 0
  end
end

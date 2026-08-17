class AddTaskManagerEnabledToDepartments < ActiveRecord::Migration[7.1]
  def change
    add_column :departments, :task_manager_enabled, :boolean, default: false, null: false
  end
end

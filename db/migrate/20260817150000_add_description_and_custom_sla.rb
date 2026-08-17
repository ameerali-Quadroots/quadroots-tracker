class AddDescriptionAndCustomSla < ActiveRecord::Migration[7.1]
  def change
    add_column :task_types, :description, :text
    add_column :tasks, :custom_sla_minutes, :integer
  end
end

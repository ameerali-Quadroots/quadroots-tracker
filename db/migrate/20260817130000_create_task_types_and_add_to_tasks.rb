class CreateTaskTypesAndAddToTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :task_types do |t|
      t.string :name, null: false
      t.references :department, null: false, foreign_key: true
      t.integer :sla_minutes, null: false, default: 0
      t.timestamps
    end
    add_index :task_types, [:department_id, :name], unique: true

    add_reference :tasks, :task_type, foreign_key: true
    add_column :tasks, :over_sla, :boolean, default: false, null: false
  end
end

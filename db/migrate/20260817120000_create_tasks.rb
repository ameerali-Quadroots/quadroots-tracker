class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.string   :title, null: false
      t.text     :description
      t.string   :priority, null: false, default: "normal"
      t.date     :due_date

      t.references :assigned_to, null: false, foreign_key: { to_table: :users }
      t.references :assigned_by, null: false, foreign_key: { to_table: :users }

      t.string   :status, null: false, default: "pending"

      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :pause_time
      t.datetime :resume_time
      t.integer  :accumulated_pause_seconds, default: 0, null: false
      t.integer  :total_duration

      t.string   :reason
      t.boolean  :auto_paused, default: false, null: false

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, [:assigned_to_id, :status]
  end
end

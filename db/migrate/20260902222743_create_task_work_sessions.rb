class CreateTaskWorkSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :task_work_sessions do |t|
      t.references :task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_seconds, null: false, default: 0
      t.timestamps
    end

    add_index :task_work_sessions, %i[user_id started_at]
  end
end

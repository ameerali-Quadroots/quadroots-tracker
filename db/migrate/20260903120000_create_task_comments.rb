class CreateTaskComments < ActiveRecord::Migration[7.1]
  def change
    create_table :task_comments do |t|
      t.references :task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    # The thread is always read newest-last for one task, so the composite
    # index serves both the lookup and the ordering.
    add_index :task_comments, %i[task_id created_at]
  end
end

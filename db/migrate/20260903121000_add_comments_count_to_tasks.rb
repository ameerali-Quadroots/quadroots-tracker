class AddCommentsCountToTasks < ActiveRecord::Migration[7.1]
  def up
    add_column :tasks, :comments_count, :integer, default: 0, null: false

    # The task list renders a comment badge per row; without a counter cache
    # that is one COUNT per row on every page load.
    execute <<~SQL
      UPDATE tasks SET comments_count = (
        SELECT COUNT(*) FROM task_comments WHERE task_comments.task_id = tasks.id
      )
    SQL
  end

  def down
    remove_column :tasks, :comments_count
  end
end

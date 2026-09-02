class BackfillTaskWorkSessions < ActiveRecord::Migration[7.1]
  def up
    say_with_time "Backfilling work sessions from completed tasks" do
      TaskWorkSession.backfill_completed_tasks!
    end
  end

  def down
    # Only the reconstructed rows are removable; live timer rows must survive.
    # Distinguishing them is not possible after the fact, so this is one-way.
    raise ActiveRecord::IrreversibleMigration
  end
end

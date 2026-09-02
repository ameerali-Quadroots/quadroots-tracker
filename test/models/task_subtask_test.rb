require "test_helper"

class TaskSubtaskTest < ActiveSupport::TestCase
  setup do
    @parent = tasks(:pending_a)
  end

  def build_subtask(parent:, assigned_to: users(:exec_web_a))
    Task.new(title: "Sub", priority: "normal", parent: parent,
             assigned_to: assigned_to, assigned_by: users(:manager_web),
             task_type: task_types(:web_build))
  end

  test "a task can have subtasks" do
    subtask = build_subtask(parent: @parent)

    assert subtask.save, subtask.errors.full_messages.to_sentence
    assert_equal [subtask], @parent.reload.subtasks.to_a
    assert subtask.subtask?
    assert @parent.parent_task?
  end

  test "a subtask cannot itself have a subtask" do
    subtask = build_subtask(parent: @parent)
    subtask.save!

    grandchild = build_subtask(parent: subtask)

    refute grandchild.valid?
    assert_includes grandchild.errors[:parent], "cannot be a subtask itself"
  end

  test "a task cannot be its own parent" do
    @parent.parent_id = @parent.id

    refute @parent.valid?
    assert_includes @parent.errors[:parent], "cannot be the task itself"
  end

  test "top_level excludes subtasks" do
    build_subtask(parent: @parent).save!

    assert_includes Task.top_level, @parent
    assert_equal 1, Task.subtasks_only.count
  end

  test "rolled up duration includes subtask hours" do
    subtask = build_subtask(parent: @parent)
    subtask.save!
    travel_to(Time.zone.parse("2026-09-01 09:00")) { subtask.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { subtask.complete! }

    assert_equal 3600, @parent.reload.rolled_up_duration_seconds
  end

  test "subtask progress counts completed children" do
    a = build_subtask(parent: @parent)
    a.save!
    b = build_subtask(parent: @parent)
    b.save!
    travel_to(Time.zone.parse("2026-09-01 09:00")) { a.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { a.complete! }

    assert_equal [1, 2], @parent.reload.subtask_progress
  end

  test "destroying a parent destroys its subtasks" do
    build_subtask(parent: @parent).save!

    assert_difference -> { Task.count }, -2 do
      @parent.destroy
    end
  end
end

require "test_helper"

# Closing a shift has to stop the clock on whatever the employee left running.
# Without this a task started on Friday keeps accruing seconds all weekend and
# the sprint hours are wrong by days, not minutes.
class TaskClockOutPauseTest < ActiveSupport::TestCase
  setup do
    @executive = users(:exec_web_a)
    @clock = TimeClock.create!(employee: @executive, clock_in: 2.hours.ago, current_state: "working")
  end

  test "clocking out pauses the task the executive left running" do
    task = tasks(:pending_a)
    task.start!

    @clock.close_out!(at: Time.current)

    assert_equal "paused", task.reload.status
    assert_includes task.reason.to_s, "Clocked out"
  end

  test "a task paused by clocking out is not auto-resumed by the next break ending" do
    task = tasks(:pending_a)
    task.start!

    @clock.close_out!(at: Time.current)
    TaskBreakSync.resume_after_break(@executive)

    assert_equal "paused", task.reload.status,
                 "clock-out pauses are manual, only break pauses come back on their own"
  end

  test "clocking out pauses every running task, not just the first" do
    first = tasks(:pending_a)
    second = Task.create!(title: "Second runner", priority: "normal", assigned_to: @executive,
                          assigned_by: users(:manager_web), task_type: task_types(:web_build))
    first.start!
    second.start!

    @clock.close_out!(at: Time.current)

    assert_equal %w[paused paused], [first.reload.status, second.reload.status]
  end

  test "clocking out leaves a paused task alone" do
    task = tasks(:pending_a)
    task.start!
    task.pause!(reason: "Waiting on copy")

    @clock.close_out!(at: Time.current)

    assert_equal "Waiting on copy", task.reload.reason, "an existing pause reason is not overwritten"
  end
end

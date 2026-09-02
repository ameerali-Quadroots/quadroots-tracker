require "test_helper"

class TaskWorkSessionBackfillTest < ActiveSupport::TestCase
  test "backfill creates one session per completed task ending at ended_at" do
    task = tasks(:pending_a)
    task.update_columns(status: "completed", total_duration: 3600,
                        started_at: Time.zone.parse("2026-09-01 09:00"),
                        ended_at: Time.zone.parse("2026-09-01 10:00"))

    assert_equal 1, TaskWorkSession.backfill_completed_tasks!

    session = task.work_sessions.sole
    assert_equal 3600, session.duration_seconds
    assert_equal Time.zone.parse("2026-09-01 10:00"), session.ended_at
    assert_equal task.assigned_to_id, session.user_id
  end

  test "backfill splits a completed task that spanned midnight" do
    task = tasks(:pending_a)
    task.update_columns(status: "completed", total_duration: 7200,
                        started_at: Time.zone.parse("2026-09-01 23:00"),
                        ended_at: Time.zone.parse("2026-09-02 01:00"))

    TaskWorkSession.backfill_completed_tasks!

    assert_equal 2, task.work_sessions.count
    assert_equal 7200, task.work_sessions.sum(:duration_seconds)
  end

  test "backfill skips tasks with no ended_at or no duration" do
    tasks(:pending_a).update_columns(status: "completed", total_duration: nil, ended_at: nil)

    assert_equal 0, TaskWorkSession.backfill_completed_tasks!
    assert_equal 0, TaskWorkSession.count
  end

  test "backfill is idempotent and never doubles a task's hours" do
    task = tasks(:pending_a)
    task.update_columns(status: "completed", total_duration: 3600,
                        started_at: Time.zone.parse("2026-09-01 09:00"),
                        ended_at: Time.zone.parse("2026-09-01 10:00"))

    TaskWorkSession.backfill_completed_tasks!
    TaskWorkSession.backfill_completed_tasks!

    assert_equal 1, task.work_sessions.count
  end
end

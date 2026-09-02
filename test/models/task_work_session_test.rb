require "test_helper"

class TaskWorkSessionTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:pending_a)
  end

  test "segments returns one segment for an interval inside a single day" do
    from = Time.zone.parse("2026-09-01 09:00")
    to   = Time.zone.parse("2026-09-01 11:30")

    segments = TaskWorkSession.segments(from, to)

    assert_equal [[from, to]], segments
  end

  test "segments splits an interval that crosses midnight" do
    from = Time.zone.parse("2026-09-01 22:00")
    to   = Time.zone.parse("2026-09-02 02:00")
    midnight = Time.zone.parse("2026-09-02 00:00")

    segments = TaskWorkSession.segments(from, to)

    assert_equal [[from, midnight], [midnight, to]], segments
  end

  test "segments splits an interval spanning three days" do
    from = Time.zone.parse("2026-09-01 23:00")
    to   = Time.zone.parse("2026-09-03 01:00")

    segments = TaskWorkSession.segments(from, to)

    assert_equal 3, segments.length
    assert_equal from, segments.first.first
    assert_equal to, segments.last.last
    assert_equal 26 * 3600, segments.sum { |a, b| (b - a).round }
  end

  test "segments returns nothing when the interval is empty or backwards" do
    now = Time.zone.parse("2026-09-01 09:00")

    assert_empty TaskWorkSession.segments(now, now)
    assert_empty TaskWorkSession.segments(now, now - 1.hour)
  end

  test "close! writes duration and leaves a single row for a same-day interval" do
    session = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 09:00"))

    session.close!(Time.zone.parse("2026-09-01 11:00"))

    assert_equal 1, TaskWorkSession.where(task_id: @task.id).count
    assert_equal 7200, session.reload.duration_seconds
    assert_equal Time.zone.parse("2026-09-01 11:00"), session.ended_at
  end

  test "close! splits a midnight-crossing session into two dated rows" do
    session = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 23:00"))

    session.close!(Time.zone.parse("2026-09-02 01:00"))

    rows = TaskWorkSession.where(task_id: @task.id).order(:started_at)
    assert_equal 2, rows.count
    assert_equal [3600, 3600], rows.map(&:duration_seconds)
    assert_equal [Date.new(2026, 9, 1), Date.new(2026, 9, 2)],
                 rows.map { |r| r.started_at.in_time_zone.to_date }
  end

  test "open_for records the task's assignee" do
    session = TaskWorkSession.open_for(@task)

    assert_equal @task.assigned_to_id, session.user_id
    assert_nil session.ended_at
  end

  test "close_for closes the newest open session and ignores closed ones" do
    old = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 09:00"))
    old.close!(Time.zone.parse("2026-09-01 10:00"))
    current = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 14:00"))

    TaskWorkSession.close_for(@task, at: Time.zone.parse("2026-09-01 15:00"))

    assert_equal 3600, current.reload.duration_seconds
    assert_equal 3600, old.reload.duration_seconds
  end

  test "close_for returns nil when there is no open session" do
    assert_nil TaskWorkSession.close_for(@task)
  end
end

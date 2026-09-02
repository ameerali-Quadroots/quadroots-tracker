require "test_helper"

class TaskTimerSessionsTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:pending_a)
  end

  test "start opens a session" do
    travel_to Time.zone.parse("2026-09-01 09:00") do
      @task.start!
    end

    assert_equal 1, @task.work_sessions.count
    assert_nil @task.work_sessions.first.ended_at
  end

  test "pause closes the open session" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { @task.pause! }

    assert_equal 1, @task.work_sessions.count
    assert_equal 3600, @task.work_sessions.first.duration_seconds
  end

  test "resume opens a second session" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { @task.pause! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { @task.resume! }

    assert_equal 2, @task.work_sessions.count
    assert_equal 1, @task.work_sessions.open_sessions.count
  end

  test "complete closes the session and total_duration equals the session sum" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { @task.pause! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { @task.resume! }
    travel_to(Time.zone.parse("2026-09-01 12:00")) { @task.complete! }

    assert_equal 7200, @task.reload.total_duration
    assert_equal 7200, @task.work_sessions.sum(:duration_seconds)
    assert_equal 0, @task.work_sessions.open_sessions.count
  end

  test "a task already in progress before sessions existed still records its time" do
    @task.update_columns(status: "in_progress", started_at: Time.zone.parse("2026-09-01 09:00"))
    assert_equal 0, @task.work_sessions.count

    travel_to(Time.zone.parse("2026-09-01 11:00")) { @task.complete! }

    assert_equal 7200, @task.reload.total_duration
  end

  test "paused time is excluded from the session sum" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 09:30")) { @task.pause! }
    travel_to(Time.zone.parse("2026-09-01 11:30")) { @task.resume! }
    travel_to(Time.zone.parse("2026-09-01 12:00")) { @task.complete! }

    # 30 min before the pause + 30 min after it; the 2h pause is not counted.
    assert_equal 3600, @task.reload.total_duration
  end

  test "a task worked across midnight produces one session row per day" do
    travel_to(Time.zone.parse("2026-09-01 23:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-02 01:00")) { @task.complete! }

    dates = @task.work_sessions.order(:started_at).map { |s| s.started_at.in_time_zone.to_date }
    assert_equal [Date.new(2026, 9, 1), Date.new(2026, 9, 2)], dates
    assert_equal 7200, @task.reload.total_duration
  end
end

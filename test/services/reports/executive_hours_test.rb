require "test_helper"

module Reports
  class ExecutiveHoursTest < ActiveSupport::TestCase
    setup do
      @department = departments(:web)
      @range = Time.zone.parse("2026-09-01 00:00")..Time.zone.parse("2026-09-07 23:59:59")
      @exec = users(:exec_web_a)
    end

    def report = Reports::ExecutiveHours.new(department: @department, range: @range)

    test "lists employed executives in the department, ordered by name" do
      names = report.executives.map(&:name)

      assert_equal ["Web Exec A", "Web Exec B"], names
      refute_includes names, "Design Exec"
      refute_includes names, "Web Manager"
    end

    test "sums task seconds per executive per day" do
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

      assert_equal 7200, report.for(@exec.id, Date.new(2026, 9, 1))[:task_seconds]
    end

    test "sums attendance seconds from time clocks without re-subtracting breaks" do
      TimeClock.create!(user_id: @exec.id,
                        clock_in: Time.zone.parse("2026-09-01 09:00"),
                        clock_out: Time.zone.parse("2026-09-01 18:00"),
                        total_duration: 28_800, break_duration: 3600)

      assert_equal 28_800, report.for(@exec.id, Date.new(2026, 9, 1))[:attendance_seconds]
    end

    test "gap is attendance minus task time, never negative" do
      TimeClock.create!(user_id: @exec.id,
                        clock_in: Time.zone.parse("2026-09-01 09:00"),
                        clock_out: Time.zone.parse("2026-09-01 18:00"),
                        total_duration: 28_800, break_duration: 0)
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

      day = report.for(@exec.id, Date.new(2026, 9, 1))
      assert_equal 21_600, day[:gap_seconds]
    end

    test "columns yields one entry per day for a week and per week for a month" do
      month = Reports::ExecutiveHours.new(
        department: @department,
        range: Time.zone.parse("2026-09-01 00:00")..Time.zone.parse("2026-09-30 23:59:59")
      )

      assert_equal 7, report.columns("week").size
      assert_equal 5, month.columns("month").size
      assert_equal "w/c 31 Aug", month.columns("month").first.first
    end

    test "bucket sums several days into one cell" do
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

      summed = report.bucket(@exec.id, [Date.new(2026, 9, 1), Date.new(2026, 9, 2)])

      assert_equal 7200, summed[:task_seconds]
    end

    test "returns zeros for a day with no activity" do
      assert_equal({ task_seconds: 0, attendance_seconds: 0, gap_seconds: 0 },
                   report.for(@exec.id, Date.new(2026, 9, 4)))
    end

    test "excludes activity outside the range" do
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-08-25 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-08-25 11:00")) { task.complete! }

      assert_equal 0, report.totals_for(@exec.id)[:task_seconds]
    end

    test "subtask hours count toward whoever worked them, not the parent's assignee" do
      subtask = Task.create!(title: "Sub", priority: "normal", parent: tasks(:pending_a),
                             assigned_to: users(:exec_web_b), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))
      travel_to(Time.zone.parse("2026-09-02 09:00")) { subtask.start! }
      travel_to(Time.zone.parse("2026-09-02 10:00")) { subtask.complete! }

      assert_equal 3600, report.for(users(:exec_web_b).id, Date.new(2026, 9, 2))[:task_seconds]
      assert_equal 0, report.for(@exec.id, Date.new(2026, 9, 2))[:task_seconds]
    end

    test "query count does not grow with the number of executives" do
      queries = []
      counter = ->(_n, _s, _f, _i, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        report.tap(&:executives).matrix
      end

      assert_operator queries.size, :<=, 4, "N+1 detected:\n#{queries.join("\n")}"
    end
  end
end

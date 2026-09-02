require "test_helper"

class TaskReportExporterTest < ActiveSupport::TestCase
  setup do
    @range = Time.zone.parse("2026-09-01 00:00")..Time.zone.parse("2026-09-07 23:59:59")
    task = tasks(:pending_a)
    travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }
    TimeClock.create!(user_id: users(:exec_web_a).id,
                      clock_in: Time.zone.parse("2026-09-01 09:00"),
                      clock_out: Time.zone.parse("2026-09-01 18:00"),
                      total_duration: 28_800, break_duration: 0)
    @exporter = TaskReportExporter.new(department: departments(:web), range: @range)
  end

  test "weekly timing has a row per executive per day with activity" do
    headers, rows = @exporter.weekly_timing

    assert_equal ["Executive", "Date", "Task Hours", "Attendance Hours", "Untracked Hours"], headers
    row = rows.find { |r| r[0] == "Web Exec A" && r[1] == "2026-09-01" }
    assert_equal [2.0, 8.0, 6.0], row[2..4]
  end

  test "monthly stats has one row per executive" do
    headers, rows = @exporter.monthly_stats

    assert_equal ["Executive", "Task Hours", "Attendance Hours", "Untracked Hours",
                  "Tasks Completed", "Over SLA", "Average Task Hours"], headers
    assert_equal 2, rows.size
    row = rows.find { |r| r[0] == "Web Exec A" }
    assert_equal 2.0, row[1]
    assert_equal 1, row[4]
  end

  test "task list exports the tasks it is given" do
    exporter = TaskReportExporter.new(department: departments(:web), range: @range,
                                      tasks: Task.where(id: tasks(:pending_a).id))

    _headers, rows = exporter.task_list

    assert_equal 1, rows.size
    assert_equal tasks(:pending_a).title, rows.first[0]
  end

  test "to_csv renders headers and rows" do
    csv = @exporter.to_csv(@exporter.weekly_timing)

    assert csv.start_with?("Executive,Date,Task Hours")
    assert_includes csv, "Web Exec A,2026-09-01,2.0"
  end

  test "to_xlsx returns a non-empty xlsx package" do
    data = @exporter.to_xlsx(@exporter.monthly_stats)

    assert data.bytesize.positive?
    assert data.start_with?("PK")
  end
end

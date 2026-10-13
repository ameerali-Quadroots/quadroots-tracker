require "test_helper"

class AttendanceAnalyticsReportTest < ActiveSupport::TestCase
  RANGE = Date.new(2026, 9, 1)..Date.new(2026, 9, 10)

  setup do
    @exec_a = users(:exec_web_a)
    @exec_b = users(:exec_web_b)
    @designer = users(:exec_design)
  end

  def report(**opts)
    Reports::AttendanceAnalytics.new(range: RANGE, **opts)
  end

  def clock_in(user, date, status: "on_time", hours: 8)
    TimeClock.create!(employee: user, status: status, total_duration: hours * 3600,
                      clock_in: Time.zone.local(date.year, date.month, date.day, 18, 30))
  end

  test "the summary counts clock-ins, lates and the on-time rate" do
    clock_in(@exec_a, Date.new(2026, 9, 1))
    clock_in(@exec_a, Date.new(2026, 9, 2), status: "late")
    clock_in(@exec_b, Date.new(2026, 9, 2))
    clock_in(@designer, Date.new(2026, 9, 3))

    summary = report.summary
    assert_equal 4, summary[:clock_ins]
    assert_equal 1, summary[:lates]
    assert_equal 75.0, summary[:on_time_rate]
  end

  test "average hours come from completed shifts only" do
    clock_in(@exec_a, Date.new(2026, 9, 1), hours: 6)
    clock_in(@exec_b, Date.new(2026, 9, 1), hours: 8)
    TimeClock.create!(employee: @designer, status: "on_time", clock_in: Time.zone.local(2026, 9, 1, 18, 0))

    assert_equal 7.0, report.summary[:avg_hours]
  end

  test "clock-ins outside the range are ignored" do
    clock_in(@exec_a, Date.new(2026, 8, 31))
    clock_in(@exec_a, Date.new(2026, 9, 11))

    assert_equal 0, report.summary[:clock_ins]
  end

  test "the last day of the range is included" do
    clock_in(@exec_a, Date.new(2026, 9, 10))

    assert_equal 1, report.summary[:clock_ins]
  end

  test "an empty period has no on-time rate rather than a misleading zero" do
    assert_nil report.summary[:on_time_rate]
  end

  test "restricting to departments drops everyone else" do
    clock_in(@exec_a, Date.new(2026, 9, 1))
    clock_in(@designer, Date.new(2026, 9, 1), status: "late")

    scoped = report(departments: ["Design"])
    assert_equal 1, scoped.summary[:clock_ins]
    assert_equal ["Design"], scoped.by_department.map { |row| row[:department] }
  end

  test "the previous period is the same length, immediately before" do
    clock_in(@exec_a, Date.new(2026, 8, 22))
    clock_in(@exec_a, Date.new(2026, 8, 31), status: "late")
    clock_in(@exec_a, Date.new(2026, 8, 21))

    assert_equal 2, report.previous_summary[:clock_ins]
    assert_equal 1, report.previous_summary[:lates]
  end

  test "the daily series has a row for every day, including empty ones" do
    clock_in(@exec_a, Date.new(2026, 9, 2), status: "late")
    clock_in(@exec_b, Date.new(2026, 9, 2))

    daily = report.daily
    assert_equal RANGE.to_a, daily.map { |day| day[:date] }
    assert_equal({ on_time: 1, late: 1 }, daily[1].slice(:on_time, :late))
    assert_equal({ on_time: 0, late: 0 }, daily[0].slice(:on_time, :late))
  end

  test "a clock-in after midnight is charted on the day its shift started" do
    TimeClock.create!(employee: @exec_a, status: "late", total_duration: 8 * 3600, clock_in: Time.zone.local(2026, 9, 3, 0, 30))

    daily = report.daily
    assert_equal 1, daily.find { |day| day[:date] == Date.new(2026, 9, 2) }[:late]
    assert_equal 0, daily.find { |day| day[:date] == Date.new(2026, 9, 3) }[:late]
  end

  test "departments are ranked by late rate" do
    clock_in(@exec_a, Date.new(2026, 9, 1), status: "late")
    clock_in(@exec_b, Date.new(2026, 9, 1))
    clock_in(@designer, Date.new(2026, 9, 1), status: "late")

    rows = report.by_department.select { |row| row[:clock_ins].positive? }
    assert_equal %w[Design Web], rows.map { |row| row[:department] }
    assert_equal [100.0, 50.0], rows.map { |row| row[:late_rate] }
  end

  test "the most late employees are listed first and those never late are left out" do
    2.times { |i| clock_in(@exec_a, Date.new(2026, 9, i + 1), status: "late") }
    clock_in(@designer, Date.new(2026, 9, 1), status: "late")
    clock_in(@exec_b, Date.new(2026, 9, 1))

    assert_equal [[@exec_a.name, 2], [@designer.name, 1]], report.top_late.map { |row| [row[:name], row[:lates]] }
  end

  test "late minutes fall into the right bucket" do
    assert_equal "1–5 min", Reports::AttendanceAnalytics.bucket_for(1)
    assert_equal "1–5 min", Reports::AttendanceAnalytics.bucket_for(5)
    assert_equal "6–15 min", Reports::AttendanceAnalytics.bucket_for(6)
    assert_equal "16–30 min", Reports::AttendanceAnalytics.bucket_for(30)
    assert_equal "31–60 min", Reports::AttendanceAnalytics.bucket_for(45)
    assert_equal "Over 1 hour", Reports::AttendanceAnalytics.bucket_for(61)
  end

  test "every late arrival lands in exactly one lateness bucket" do
    3.times { |i| clock_in(@exec_a, Date.new(2026, 9, i + 1), status: "late") }
    clock_in(@exec_b, Date.new(2026, 9, 1))

    assert_equal 3, report.lateness_buckets.values.sum
    assert_equal Reports::AttendanceAnalytics::BUCKETS.map(&:first), report.lateness_buckets.keys
  end

  test "leaves are counted by type and rejected ones are left out" do
    Leave.delete_all
    Leave.create!(user: @exec_a, leave_type: "casual", status: "approved", reason: "x",
                  start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 9, 2))
    Leave.create!(user: @exec_b, leave_type: "medical", status: "pending", reason: "x",
                  start_date: Date.new(2026, 9, 3), end_date: Date.new(2026, 9, 3))
    Leave.create!(user: @exec_b, leave_type: "casual", status: "rejected", reason: "x",
                  start_date: Date.new(2026, 9, 3), end_date: Date.new(2026, 9, 3))

    assert_equal({ "casual" => 1, "medical" => 1 }, report.leaves_by_type)
  end
end

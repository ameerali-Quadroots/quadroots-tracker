require "test_helper"

class EmployeeMonthReportTest < ActiveSupport::TestCase
  MONTH = Date.new(2026, 9, 1)

  setup do
    @user = users(:exec_web_a)
    @other = users(:exec_web_b)
    AppSetting.instance.update!(late_kpi_monthly_limit: 3, edit_request_monthly_limit: 3)
  end

  def report(month: MONTH, today: Date.new(2026, 9, 30))
    Reports::EmployeeMonth.new(user: @user, month: month, today: today)
  end

  def clock_in(day, status: "on_time", hours: 8, user: @user, month: MONTH)
    TimeClock.create!(employee: user, status: status, total_duration: hours * 3600,
                      clock_in: Time.zone.local(month.year, month.month, day, 18, 20),
                      clock_out: Time.zone.local(month.year, month.month, day, 18, 20) + hours.hours)
  end

  def edit_request(day, status: "pending", type: "Forgot to end break")
    request = EditRequest.new(user: @user, time_clock: clock_in(day), request_type: type, status: status, reason: "x",
                              created_at: Time.zone.local(2026, 9, day, 20, 0))
    request.save!(validate: false)
    request
  end

  test "counts only this employee's days in the month" do
    clock_in(1); clock_in(2, status: "late")
    clock_in(3, user: @other)
    clock_in(1, month: Date.new(2026, 8, 1))

    assert_equal 2, report.days_worked
    assert_equal 1, report.lates
    assert_equal 50.0, report.on_time_rate
  end

  test "a clock-in after midnight counts on the day the shift started" do
    TimeClock.create!(employee: @user, status: "late", total_duration: 6 * 3600, clock_in: Time.zone.local(2026, 9, 8, 0, 30))

    r = report
    assert_equal [Date.new(2026, 9, 7)], r.late_days.map { |day| day[:date] }
    assert_equal 6.0, r.daily.find { |day| day[:date] == Date.new(2026, 9, 7) }[:hours]
    assert_equal 0.0, r.daily.find { |day| day[:date] == Date.new(2026, 9, 8) }[:hours]
  end

  test "a clock-in in the early hours of the 1st belongs to the previous month" do
    TimeClock.create!(employee: @user, status: "late", clock_in: Time.zone.local(2026, 10, 1, 0, 30))
    TimeClock.create!(employee: @user, status: "late", clock_in: Time.zone.local(2026, 9, 1, 0, 30))

    assert_equal 1, report.lates
    assert_equal [Date.new(2026, 9, 30)], report.late_days.map { |day| day[:date] }
  end

  test "an empty month has no on-time rate" do
    assert_nil report.on_time_rate
    assert_equal 0, report.days_worked
  end

  test "lates left counts down to the KPI limit and the flag trips only once over it" do
    3.times { |i| clock_in(i + 1, status: "late") }

    at_limit = report
    assert_equal 0, at_limit.lates_left
    assert_not at_limit.kpi_deducted?

    clock_in(4, status: "late")
    over = report
    assert_equal 0, over.lates_left
    assert over.kpi_deducted?
  end

  test "late days are listed newest first with the day they happened" do
    clock_in(2, status: "late"); clock_in(9, status: "late"); clock_in(5)

    assert_equal [Date.new(2026, 9, 9), Date.new(2026, 9, 2)], report.late_days.map { |day| day[:date] }
  end

  test "hours are totalled and averaged over completed shifts" do
    clock_in(1, hours: 8); clock_in(2, hours: 6)
    TimeClock.create!(employee: @user, status: "on_time", clock_in: Time.zone.local(2026, 9, 3, 18, 0))

    assert_equal 14.0, report.total_hours
    assert_equal 7.0, report.average_hours
  end

  test "the average clock-in is the mean arrival, even when a shift starts after midnight" do
    TimeClock.create!(employee: @user, status: "on_time", clock_in: Time.zone.local(2026, 9, 1, 18, 10))
    TimeClock.create!(employee: @user, status: "on_time", clock_in: Time.zone.local(2026, 9, 2, 18, 30))
    assert_equal "06:20 PM", report.average_clock_in.strftime("%I:%M %p")

    # An arrival at 00:30 belongs to the evening shift that started the day before.
    TimeClock.create!(employee: @user, status: "late", clock_in: Time.zone.local(2026, 9, 4, 0, 20))
    assert_equal "08:20 PM", report.average_clock_in.strftime("%I:%M %p")
  end

  test "the daily series covers each day of the month up to today" do
    clock_in(2, hours: 8, status: "late")

    daily = report(today: Date.new(2026, 9, 3)).daily
    assert_equal [Date.new(2026, 9, 1), Date.new(2026, 9, 2), Date.new(2026, 9, 3)], daily.map { |day| day[:date] }
    assert_equal({ hours: 8.0, status: "late" }, daily[1].slice(:hours, :status))
    assert_equal({ hours: 0.0, status: nil }, daily[0].slice(:hours, :status))
  end

  test "a past month's daily series runs to the end of that month" do
    assert_equal 31, report(month: Date.new(2026, 8, 1)).daily.size
  end

  test "edit requests are counted against the monthly limit by the day they were submitted" do
    edit_request(4); edit_request(11, status: "approved")
    old = edit_request(1); old.update_columns(created_at: Time.zone.local(2026, 8, 20, 12, 0))

    r = report
    assert_equal 2, r.edit_requests_used
    assert_equal 3, r.edit_request_limit
    assert_equal 1, r.edit_requests_left
    assert_equal [Date.new(2026, 9, 11), Date.new(2026, 9, 4)], r.edit_requests.map { |request| request.created_at.to_date }
  end

  test "edit requests left never goes below zero" do
    4.times { |i| edit_request(i + 1) }

    assert_equal 0, report.edit_requests_left
  end

  test "the on-time streak counts back from the most recent shift and stops at a late one" do
    clock_in(1); clock_in(2, status: "late"); clock_in(3); clock_in(4)

    assert_equal 2, report.on_time_streak
  end

  test "leave in the month is grouped by type, ignoring rejected requests" do
    Leave.delete_all
    Leave.create!(user: @user, leave_type: "casual", status: "approved", reason: "x", start_date: Date.new(2026, 9, 7), end_date: Date.new(2026, 9, 7))
    Leave.create!(user: @user, leave_type: "casual", status: "rejected", reason: "x", start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 8))
    Leave.create!(user: @user, leave_type: "medical", status: "pending", reason: "x", start_date: Date.new(2026, 9, 9), end_date: Date.new(2026, 9, 9))

    assert_equal({ "casual" => 1, "medical" => 1 }, report.leaves_by_type)
  end
end

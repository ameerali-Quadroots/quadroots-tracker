require "test_helper"

class LateKpiReportTest < ActiveSupport::TestCase
  MONTH = Date.new(2026, 9, 1)

  setup do
    @exec_a = users(:exec_web_a)
    @exec_b = users(:exec_web_b)
    @designer = users(:exec_design)
  end

  def report(**opts)
    Reports::LateKpi.new(month: MONTH, limit: 3, **opts)
  end

  def clock_in(user, day:, status: "late", month: MONTH)
    TimeClock.create!(employee: user, status: status,
                      clock_in: Time.zone.local(month.year, month.month, day, 18, 30))
  end

  def row_for(user, rep = report)
    rep.rows.find { |row| row.user == user }
  end

  test "an employee at the limit is not flagged" do
    3.times { |i| clock_in(@exec_a, day: i + 1) }

    row = row_for(@exec_a)
    assert_equal 3, row.late_count
    assert_not row.kpi_deducted
  end

  test "an employee over the limit is flagged as KPI deducted" do
    4.times { |i| clock_in(@exec_a, day: i + 1) }

    row = row_for(@exec_a)
    assert_equal 4, row.late_count
    assert row.kpi_deducted
  end

  test "on-time clock-ins do not count towards the limit" do
    4.times { |i| clock_in(@exec_a, day: i + 1, status: "on_time") }

    assert_equal 0, row_for(@exec_a).late_count
  end

  test "lates from other months are ignored" do
    4.times { |i| clock_in(@exec_a, day: i + 1, month: Date.new(2026, 8, 1)) }
    clock_in(@exec_a, day: 1)

    row = row_for(@exec_a)
    assert_equal 1, row.late_count
    assert_not row.kpi_deducted
  end

  test "the last day of the month still belongs to that month" do
    clock_in(@exec_a, day: 30)

    assert_equal 1, row_for(@exec_a).late_count
  end

  test "a late clock-in after midnight on the 1st counts towards the previous month" do
    # 00:40 on 1 Oct is the tail of the 30 Sep shift; 00:40 on 1 Sep is the tail of 31 Aug.
    TimeClock.create!(employee: @exec_a, status: "late", clock_in: Time.zone.local(2026, 10, 1, 0, 40))
    TimeClock.create!(employee: @exec_b, status: "late", clock_in: Time.zone.local(2026, 9, 1, 0, 40))

    assert_equal 1, row_for(@exec_a).late_count
    assert_equal 0, row_for(@exec_b).late_count
  end

  test "employees with no lates are still listed" do
    assert_equal 0, row_for(@exec_b).late_count
  end

  test "former employees are left out" do
    @exec_b.update!(employeed: false)

    assert_nil row_for(@exec_b)
  end

  test "flagged employees are listed first" do
    4.times { |i| clock_in(@designer, day: i + 1) }

    assert_equal @designer, report.rows.first.user
  end

  test "flagged rows are only the KPI deducted employees" do
    4.times { |i| clock_in(@exec_a, day: i + 1) }
    clock_in(@exec_b, day: 1)

    assert_equal [@exec_a], report.flagged_rows.map(&:user)
  end

  test "the department summary totals employees, lates and flagged employees" do
    4.times { |i| clock_in(@exec_a, day: i + 1) }
    clock_in(@exec_b, day: 1)

    web = report.department_summary.find { |summary| summary.department == "Web" }
    assert_equal User.employed.where(department: "Web").count, web.total_employees
    assert_equal 5, web.total_lates
    assert_equal 1, web.flagged_count
  end

  test "restricting to departments drops everyone else" do
    scoped = report(departments: ["Design"])

    assert_equal ["Design"], scoped.rows.map(&:department).uniq
    assert_equal ["Design"], scoped.department_summary.map(&:department)
  end

  test "the limit defaults to the configured setting" do
    AppSetting.instance.update!(late_kpi_monthly_limit: 1)
    2.times { |i| clock_in(@exec_a, day: i + 1) }

    assert row_for(@exec_a, Reports::LateKpi.new(month: MONTH)).kpi_deducted
  end
end

require "test_helper"

class TaskDashboardReportTest < ActiveSupport::TestCase
  setup do
    @manager = users(:manager_web)
    @executive = users(:exec_web_a)
    @scope = Task.joins(:assigned_to).where(users: { department_id: @manager.department_id })
    @executives = User.where(id: [@executive.id, users(:exec_web_b).id])
  end

  def report(range: Date.current.all_week, previous_range: nil)
    Reports::TaskDashboard.new(scope: @scope, executives: @executives,
                               range: range, previous_range: previous_range)
  end

  def make(title:, status: "pending", **attrs)
    Task.create!({ title: title, priority: "normal", status: status,
                   assigned_to: @executive, assigned_by: @manager,
                   task_type: task_types(:web_build) }.merge(attrs))
  end

  test "in flight counts everything somebody still has to act on" do
    make(title: "Waiting", status: "pending")
    make(title: "Going", status: "in_progress", started_at: 1.hour.ago)
    make(title: "Held", status: "paused", started_at: 2.hours.ago, pause_time: 1.hour.ago)
    make(title: "Finished", status: "completed", total_duration: 60)

    # tasks(:pending_a) is a pending fixture task, so it counts too.
    assert_equal 4, report.in_flight
    assert_equal 5, report.total_tasks
  end

  test "on time rate is nil rather than a perfect score when nothing is done" do
    assert_nil report.on_time_rate
  end

  test "on time rate measures only finished work" do
    make(title: "Inside", status: "completed", total_duration: 60, over_sla: false)
    make(title: "Inside too", status: "completed", total_duration: 60, over_sla: false)
    make(title: "Outside", status: "completed", total_duration: 99_999, over_sla: true)
    make(title: "Still going", status: "in_progress", started_at: 1.hour.ago)

    assert_equal 67, report.on_time_rate
  end

  test "over sla counts a running task that has already passed its budget" do
    quick = TaskType.create!(name: "One minute", department: departments(:web), sla_minutes: 1)
    running = make(title: "Long runner", task_type: quick)
    travel_to(3.hours.ago) { running.start! }

    # Nothing is stored on the record — the breach is a function of the clock.
    assert_equal false, running.reload.over_sla
    assert_equal 1, report.over_sla_count
  end

  test "over sla ignores a task that has not been started" do
    quick = TaskType.create!(name: "Also one minute", department: departments(:web), sla_minutes: 1)
    make(title: "Not started yet", task_type: quick)

    assert_equal 0, report.over_sla_count
  end

  test "workload is ordered with the busiest executive first" do
    other = users(:exec_web_b)
    3.times { |i| make(title: "For B #{i}", assigned_to: other) }

    names = report.workload_by_executive.map(&:first)
    assert_equal other.name, names.first
    assert_includes names, @executive.name
  end

  test "workload splits each executive's tasks by status" do
    make(title: "Going", status: "in_progress", started_at: 1.hour.ago)

    row = report.workload_by_executive.detect { |name, _| name == @executive.name }
    assert_equal 1, row.last["in_progress"]
    assert_equal 1, row.last["pending"]
  end

  test "throughput has one zero filled point per day and no gaps" do
    points = report.throughput

    assert_equal Reports::TaskDashboard::THROUGHPUT_DAYS, points.size
    assert_equal Date.current, points.last.first
    assert points.all? { |_day, count| count.is_a?(Integer) }
  end

  test "throughput counts a task on the day it was completed" do
    make(title: "Done yesterday", status: "completed", total_duration: 60,
         ended_at: 1.day.ago.change(hour: 12))

    counted = report.throughput.to_h
    assert_equal 1, counted[1.day.ago.to_date]
    assert_equal 0, counted[Date.current]
  end

  test "logged seconds sums only sessions inside the range" do
    TaskWorkSession.create!(task: tasks(:pending_a), user: @executive,
                            started_at: Time.current.beginning_of_day + 9.hours,
                            ended_at: Time.current.beginning_of_day + 11.hours,
                            duration_seconds: 7_200)
    TaskWorkSession.create!(task: tasks(:pending_a), user: @executive,
                            started_at: 40.days.ago, ended_at: 40.days.ago + 1.hour,
                            duration_seconds: 3_600)

    assert_equal 7_200, report.logged_seconds
  end

  test "the delta compares the range against the one before it" do
    this_week = Date.current.all_week
    last_week = (Date.current - 1.week).all_week

    TaskWorkSession.create!(task: tasks(:pending_a), user: @executive,
                            started_at: this_week.first + 9.hours,
                            ended_at: this_week.first + 12.hours, duration_seconds: 10_800)
    TaskWorkSession.create!(task: tasks(:pending_a), user: @executive,
                            started_at: last_week.first + 9.hours,
                            ended_at: last_week.first + 10.hours, duration_seconds: 3_600)

    r = report(range: this_week, previous_range: last_week)
    assert_equal 10_800, r.logged_seconds
    assert_equal 3_600, r.previous_logged_seconds
    assert_equal 7_200, r.logged_delta_seconds
  end

  test "the delta is nil when there is nothing to compare against" do
    assert_nil report.logged_delta_seconds
  end

  # This is the codebase's known performance hazard, so it is asserted rather
  # than assumed: the figures must come from grouped aggregates, not from
  # walking the records. The test pins the *invariance* — the same handful of
  # queries whether the department holds three tasks or thirty — rather than an
  # exact number, which would break on any harmless extra memoized load.
  test "the summary figures do not grow their query count with the number of tasks" do
    # Warm the executives relation first — it caches its own records, and that
    # one-off load would otherwise show up as a difference between the runs.
    @executives.load
    baseline = count_queries { read_every_figure(report) }

    30.times { |i| make(title: "Bulk #{i}") }

    assert_equal baseline, count_queries { read_every_figure(report) },
                 "the dashboard figures must not issue a query per task"
  end

  def read_every_figure(report)
    report.counts_by_status
    report.workload_by_executive
    report.throughput
    report.logged_seconds
    report.completed_over_sla
  end

  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT")
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

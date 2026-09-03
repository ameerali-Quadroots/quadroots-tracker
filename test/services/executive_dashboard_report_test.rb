require "test_helper"

class ExecutiveDashboardReportTest < ActiveSupport::TestCase
  setup do
    @executive = users(:exec_web_a)
    @manager = users(:manager_web)
  end

  def report
    tasks = Task.for_executive(@executive).includes(:task_type).order(created_at: :desc)
    Reports::ExecutiveDashboard.new(user: @executive, tasks: tasks)
  end

  def make(title:, **attrs)
    Task.create!({ title: title, priority: "normal", assigned_to: @executive,
                   assigned_by: @manager, task_type: task_types(:web_build) }.merge(attrs))
  end

  test "the running task is the one the timer is on" do
    going = make(title: "Actually going")
    going.start!

    assert_equal going, report.running_task
  end

  test "there is no running task when nothing has been started" do
    assert_nil report.running_task
  end

  test "next up prefers the earliest due date" do
    make(title: "Due later", due_date: 5.days.from_now)
    soonest = make(title: "Due sooner", due_date: 1.day.from_now)

    assert_equal soonest, report.next_up
  end

  test "next up breaks a due-date tie on urgency" do
    same_day = 2.days.from_now
    make(title: "Normal one", due_date: same_day, priority: "normal")
    urgent = make(title: "Urgent one", due_date: same_day, priority: "urgent")

    assert_equal urgent, report.next_up
  end

  test "next up ignores work that is already under way" do
    going = make(title: "Under way", due_date: 1.day.from_now)
    going.start!
    waiting = make(title: "Still waiting", due_date: 3.days.from_now)

    assert_equal waiting, report.next_up
  end

  test "paused tasks are listed so they can be resumed" do
    held = make(title: "On hold")
    held.start!
    held.pause!(reason: "Waiting on the client")

    assert_equal [held], report.paused_tasks
  end

  test "the trend has one zero filled point per day" do
    points = report.trend

    assert_equal Reports::ExecutiveDashboard::TREND_DAYS, points.size
    assert_equal Date.current, points.last.first
    assert points.all? { |_day, seconds| seconds.is_a?(Integer) }
  end

  test "hours logged today are separated from the rest of the week" do
    task = make(title: "Timed work")
    TaskWorkSession.create!(task: task, user: @executive,
                            started_at: Time.current.beginning_of_day + 9.hours,
                            ended_at: Time.current.beginning_of_day + 11.hours,
                            duration_seconds: 7_200)
    TaskWorkSession.create!(task: task, user: @executive,
                            started_at: 2.days.ago.change(hour: 10),
                            ended_at: 2.days.ago.change(hour: 11),
                            duration_seconds: 3_600)

    r = report
    assert_equal 7_200, r.seconds_today
    assert_equal 10_800, r.seconds_this_week
  end

  test "another executive's sessions never land in these figures" do
    other_task = Task.create!(title: "Not mine", priority: "normal",
                              assigned_to: users(:exec_web_b), assigned_by: @manager,
                              task_type: task_types(:web_build))
    TaskWorkSession.create!(task: other_task, user: users(:exec_web_b),
                            started_at: Time.current.beginning_of_day + 9.hours,
                            ended_at: Time.current.beginning_of_day + 17.hours,
                            duration_seconds: 28_800)

    assert_equal 0, report.seconds_today
  end

  test "on time rate is nil until something has been completed" do
    assert_nil report.on_time_rate
  end

  test "on time rate counts finished tasks that stayed inside their budget" do
    make(title: "Inside", status: "completed", total_duration: 60, over_sla: false)
    make(title: "Outside", status: "completed", total_duration: 99_999, over_sla: true)

    assert_equal 50, report.on_time_rate
  end

  test "open count covers everything not yet finished" do
    make(title: "Waiting")
    going = make(title: "Going")
    going.start!
    make(title: "Done", status: "completed", total_duration: 60)

    # tasks(:pending_a) belongs to this executive as well.
    assert_equal 3, report.open_count
    assert_equal 1, report.completed_count
  end
end

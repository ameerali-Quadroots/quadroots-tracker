require "test_helper"

class SprintTest < ActiveSupport::TestCase
  setup { @sprint = sprints(:crm_week_one) }

  test "a sprint reaches its department through project and client" do
    assert_equal departments(:web), @sprint.department
  end

  test "end date must not precede start date" do
    @sprint.end_date = @sprint.start_date - 1.day

    refute @sprint.valid?
    assert_includes @sprint.errors[:end_date], "must be on or after the start date"
  end

  test "sprint name is unique within a project" do
    duplicate = Sprint.new(project: projects(:crm), name: "Week 1",
                           start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 14))

    refute duplicate.valid?
  end

  test "progress counts completed tasks" do
    a = Task.create!(title: "A", priority: "normal", sprint: @sprint, assigned_to: users(:exec_web_a),
                     assigned_by: users(:manager_web), task_type: task_types(:web_build))
    Task.create!(title: "B", priority: "normal", sprint: @sprint, assigned_to: users(:exec_web_a),
                 assigned_by: users(:manager_web), task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { a.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { a.complete! }

    assert_equal [1, 2], @sprint.reload.progress
  end

  test "logged seconds sums the work sessions of the sprint's tasks" do
    task = Task.create!(title: "A", priority: "normal", sprint: @sprint, assigned_to: users(:exec_web_a),
                        assigned_by: users(:manager_web), task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

    assert_equal 7200, @sprint.reload.logged_seconds
  end

  test "a client's name is unique inside a department but reusable across departments" do
    duplicate = Client.new(name: "GN Exteriors", department: departments(:web))
    refute duplicate.valid?

    other_department = Client.new(name: "GN Exteriors", department: departments(:design))
    assert other_department.valid?
  end
end

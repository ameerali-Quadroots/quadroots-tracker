require "test_helper"

class TasksDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    sign_in @manager
  end

  test "dashboard shows tasks assigned by another manager in the same department" do
    other_manager = User.create!(
      email: "other.manager@example.com", password: "password123", name: "Other Manager",
      role_id: roles(:manager).id, department_id: departments(:web).id, employeed: true
    )
    UserManager.create!(user: users(:exec_web_b), manager: other_manager)
    task = Task.create!(title: "Assigned by peer", priority: "normal",
                        assigned_to: users(:exec_web_b), assigned_by: other_manager,
                        task_type: task_types(:web_build))

    get dashboard_tasks_path

    assert_response :success
    assert_includes response.body, task.title
  end

  test "dashboard never shows another department's tasks" do
    design_manager = User.create!(
      email: "design.manager@example.com", password: "password123", name: "Design Manager",
      role_id: roles(:manager).id, department_id: departments(:design).id, employeed: true
    )
    hidden = Task.create!(title: "Design department secret", priority: "normal",
                          assigned_to: users(:exec_design), assigned_by: design_manager,
                          task_type: TaskType.create!(name: "Mock", department: departments(:design), sla_minutes: 10))

    get dashboard_tasks_path

    refute_includes response.body, hidden.title
  end

  test "dashboard renders the team hours tab with every department executive" do
    get dashboard_tasks_path

    assert_response :success
    assert_includes response.body, "Team Hours"
    assert_includes response.body, "Web Exec A"
    assert_includes response.body, "Web Exec B"
  end

  test "subtasks are not listed as top level rows" do
    Task.create!(title: "A subtask row", priority: "normal", parent: tasks(:pending_a),
                 assigned_to: users(:exec_web_a), assigned_by: @manager,
                 task_type: task_types(:web_build))

    get dashboard_tasks_path

    assert_equal 1, css_select("tbody tr.task-row--top").size
  end

  # .dashboard-glass sets backdrop-filter, which makes it a containing block for
  # position:fixed descendants — a modal nested inside it sizes against the
  # wrapper instead of the viewport and renders as a stuck dark overlay.
  test "modals render outside the backdrop-filtered wrapper" do
    get dashboard_tasks_path

    %w[importTasksModal newSprintModal newClientModal newProjectModal newTaskModal].each do |modal_id|
      assert_select "##{modal_id}", 1, "#{modal_id} should exist"
      assert_select ".dashboard-glass ##{modal_id}", false,
                    "#{modal_id} must not be nested inside .dashboard-glass"
    end
  end

  test "week param moves the hours window" do
    get dashboard_tasks_path(week_start: "2026-09-07")

    assert_response :success
    assert_includes response.body, "07 Sep"
  end
end

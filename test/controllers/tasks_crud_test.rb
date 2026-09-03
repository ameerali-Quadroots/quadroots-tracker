require "test_helper"

class TasksCrudTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    @task = tasks(:pending_a)
  end

  def other_department_task
    design_manager = User.create!(email: "dm.crud@example.com", password: "password123", name: "DM",
                                  role_id: roles(:manager).id, department_id: departments(:design).id,
                                  employeed: true)
    Task.create!(title: "Design only", priority: "normal", assigned_to: users(:exec_design),
                 assigned_by: design_manager,
                 task_type: TaskType.create!(name: "DX", department: departments(:design), sla_minutes: 5))
  end

  # --- show (the popup) ---

  test "manager opens a task detail popup for a department task" do
    sign_in @manager
    get task_path(@task)

    assert_response :success
    assert_includes response.body, @task.title
    assert_select ".tm-drawer__head"
  end

  test "the popup shows subtasks and logged time" do
    sub = Task.create!(title: "Child bit", priority: "normal", parent: @task,
                       assigned_to: users(:exec_web_a), assigned_by: @manager,
                       task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { sub.start! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { sub.complete! }

    sign_in @manager
    get task_path(@task)

    assert_includes response.body, "Child bit"
    assert_includes response.body, "2h 0m"
  end

  test "manager cannot open another department's task" do
    hidden = other_department_task
    sign_in @manager

    get task_path(hidden)

    assert_redirected_to root_path
  end

  test "an executive can open their own task" do
    sign_in users(:exec_web_a)
    get task_path(@task)

    assert_response :success
  end

  test "an executive cannot open someone else's task" do
    others = Task.create!(title: "Not mine", priority: "normal", assigned_to: users(:exec_web_b),
                          assigned_by: @manager, task_type: task_types(:web_build))
    sign_in users(:exec_web_a)

    get task_path(others)

    assert_redirected_to root_path
  end

  # --- update ---

  test "manager edits a task" do
    sign_in @manager
    patch task_path(@task), params: { task: { title: "Renamed", priority: "urgent" } }

    assert_equal "Renamed", @task.reload.title
    assert_equal "urgent", @task.priority
  end

  test "manager moves a task to a sprint" do
    sign_in @manager
    patch task_path(@task), params: { task: { sprint_id: sprints(:crm_week_one).id } }

    assert_equal sprints(:crm_week_one).id, @task.reload.sprint_id
  end

  test "manager cannot edit another department's task" do
    hidden = other_department_task
    sign_in @manager

    patch task_path(hidden), params: { task: { title: "Hijacked" } }

    assert_redirected_to root_path
    refute_equal "Hijacked", hidden.reload.title
  end

  test "an executive cannot edit a task" do
    sign_in users(:exec_web_a)
    patch task_path(@task), params: { task: { title: "Nope" } }

    assert_redirected_to root_path
    refute_equal "Nope", @task.reload.title
  end

  # --- destroy ---

  test "manager deletes a task and its subtasks" do
    Task.create!(title: "Doomed child", priority: "normal", parent: @task,
                 assigned_to: users(:exec_web_a), assigned_by: @manager,
                 task_type: task_types(:web_build))
    sign_in @manager

    assert_difference -> { Task.count }, -2 do
      delete task_path(@task)
    end
  end

  test "an executive cannot delete a task" do
    sign_in users(:exec_web_a)

    assert_no_difference -> { Task.count } do
      delete task_path(@task)
    end
  end
end

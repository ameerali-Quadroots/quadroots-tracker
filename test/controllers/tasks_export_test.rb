require "test_helper"

class TasksExportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "weekly timing downloads as csv" do
    get export_tasks_path(report: "weekly_timing", format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Executive,Date,Task Hours"
  end

  test "monthly stats downloads as xlsx" do
    get export_tasks_path(report: "monthly_stats", format: :xlsx)

    assert_response :success
    assert response.body.start_with?("PK")
  end

  test "an unknown report name is rejected" do
    get export_tasks_path(report: "everything", format: :csv)

    assert_redirected_to dashboard_tasks_path
  end

  test "the task list export only contains this department's tasks" do
    design_manager = User.create!(email: "dm@example.com", password: "password123", name: "DM",
                                  role_id: roles(:manager).id, department_id: departments(:design).id,
                                  employeed: true)
    Task.create!(title: "Design only task", priority: "normal", assigned_to: users(:exec_design),
                 assigned_by: design_manager,
                 task_type: TaskType.create!(name: "X", department: departments(:design), sla_minutes: 5))

    get export_tasks_path(report: "task_list", format: :csv)

    refute_includes response.body, "Design only task"
  end
end

require "test_helper"

class TasksSprintsTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "sprints tab lists the department's sprints with progress" do
    get dashboard_tasks_path(tab: "sprints")

    assert_response :success
    assert_includes response.body, "GN Exteriors"
    assert_includes response.body, "Week 1"
  end

  test "sprints tab hides another department's sprints" do
    design_client = Client.create!(name: "Hidden Client", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "Hidden Project")
    Sprint.create!(project: design_project, name: "Hidden Sprint",
                   start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    get dashboard_tasks_path(tab: "sprints")

    refute_includes response.body, "Hidden Sprint"
  end

  test "sprint_id filters the tasks tab" do
    in_sprint = Task.create!(title: "Sprint work", priority: "normal", sprint: sprints(:crm_week_one),
                             assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))

    get dashboard_tasks_path(sprint_id: sprints(:crm_week_one).id)

    assert_includes response.body, in_sprint.title
    refute_includes response.body, tasks(:pending_a).title
  end
end

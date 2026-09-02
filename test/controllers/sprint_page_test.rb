require "test_helper"

class SprintPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    @sprint = sprints(:crm_week_one)
    sign_in @manager
  end

  test "sprint page shows client, project and goal" do
    get sprint_path(@sprint)

    assert_response :success
    assert_includes response.body, "GN Exteriors"
    assert_includes response.body, "CRM"
    assert_includes response.body, "Auth and contacts"
  end

  test "sprint page groups tasks into status columns" do
    Task.create!(title: "Waiting task", priority: "normal", sprint: @sprint,
                 assigned_to: users(:exec_web_a), assigned_by: @manager,
                 task_type: task_types(:web_build))
    done = Task.create!(title: "Finished task", priority: "normal", sprint: @sprint,
                        assigned_to: users(:exec_web_b), assigned_by: @manager,
                        task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { done.start! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { done.complete! }

    get sprint_path(@sprint)

    assert_select ".sprint-column", 4
    assert_select ".sprint-column[data-status=pending] .task-card", 1
    assert_select ".sprint-column[data-status=completed] .task-card", 1
    assert_includes response.body, "Waiting task"
  end

  test "sprint page reports hours logged per executive" do
    task = Task.create!(title: "Timed", priority: "normal", sprint: @sprint,
                        assigned_to: users(:exec_web_a), assigned_by: @manager,
                        task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
    travel_to(Time.zone.parse("2026-09-01 12:00")) { task.complete! }

    get sprint_path(@sprint)

    assert_select ".sprint-people", text: /Web Exec A/
    assert_includes response.body, "3h 0m"
  end

  test "a sprint from another department is not reachable" do
    other = Client.create!(name: "Other Co", department: departments(:design))
    project = Project.create!(client: other, name: "P")
    foreign = Sprint.create!(project: project, name: "W9",
                             start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    get sprint_path(foreign)

    assert_redirected_to root_path
  end

  test "an executive cannot open the sprint page" do
    sign_out @manager
    sign_in users(:exec_web_a)

    get sprint_path(@sprint)

    assert_redirected_to root_path
  end
end

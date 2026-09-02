require "test_helper"

class SprintsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "creates a client in the manager's department" do
    assert_difference -> { Client.count }, 1 do
      post clients_path, params: { client: { name: "New Client" } }
    end

    assert_equal departments(:web).id, Client.order(:id).last.department_id
  end

  test "creates a sprint under a project in the manager's department" do
    assert_difference -> { Sprint.count }, 1 do
      post sprints_path, params: { sprint: { project_id: projects(:crm).id, name: "Week 2",
                                             start_date: "2026-09-08", end_date: "2026-09-14" } }
    end
  end

  test "refuses to create a sprint under another department's project" do
    design_client = Client.create!(name: "Other", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")

    assert_no_difference -> { Sprint.count } do
      post sprints_path, params: { sprint: { project_id: design_project.id, name: "W1",
                                             start_date: "2026-09-08", end_date: "2026-09-14" } }
    end
  end

  test "carry over moves unfinished tasks to the target sprint and leaves completed ones" do
    target = Sprint.create!(project: projects(:crm), name: "Week 2",
                            start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 14))
    open_task = Task.create!(title: "Still open", priority: "normal", sprint: sprints(:crm_week_one),
                             assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))
    done_task = Task.create!(title: "Done", priority: "normal", sprint: sprints(:crm_week_one),
                             assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { done_task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { done_task.complete! }

    post carry_over_sprint_path(sprints(:crm_week_one)), params: { target_sprint_id: target.id }

    assert_equal target.id, open_task.reload.sprint_id
    assert_equal sprints(:crm_week_one).id, done_task.reload.sprint_id
  end
end

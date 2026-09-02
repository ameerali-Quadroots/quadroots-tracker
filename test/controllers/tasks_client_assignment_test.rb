require "test_helper"

class TasksClientAssignmentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "the new task form offers the department's sprints grouped by client and project" do
    get dashboard_tasks_path

    assert_response :success
    assert_select "#newTaskModal select[name=?]", "task[sprint_id]"
    assert_select "#newTaskModal optgroup[label=?]", "GN Exteriors — CRM"
  end

  test "creating a task with a sprint attaches it to that client's work" do
    assert_difference -> { Task.count }, 1 do
      post tasks_path, params: { task: {
        title: "CRM login page", priority: "normal",
        assigned_to_id: users(:exec_web_a).id,
        task_type_id: task_types(:web_build).id,
        sprint_id: sprints(:crm_week_one).id
      } }
    end

    task = Task.find_by(title: "CRM login page")
    assert_equal sprints(:crm_week_one).id, task.sprint_id
    assert_equal "GN Exteriors", task.sprint.project.client.name
  end

  test "a task cannot be created against another department's sprint" do
    design_client = Client.create!(name: "Other Co", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")
    foreign = Sprint.create!(project: design_project, name: "W1",
                             start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    assert_no_difference -> { Task.count } do
      post tasks_path, params: { task: {
        title: "Sneaky", priority: "normal",
        assigned_to_id: users(:exec_web_a).id,
        task_type_id: task_types(:web_build).id,
        sprint_id: foreign.id
      } }
    end
  end

  test "the tasks table shows which client each task belongs to" do
    Task.create!(title: "CRM login page", priority: "normal", sprint: sprints(:crm_week_one),
                 assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                 task_type: task_types(:web_build))

    get dashboard_tasks_path

    assert_select "td.task-client", text: /GN Exteriors/
    assert_select "td.task-client", text: /CRM · Week 1/
  end

  test "a task with no sprint shows a dash rather than blank" do
    get dashboard_tasks_path

    assert_select "td.task-client", text: "—"
  end
end

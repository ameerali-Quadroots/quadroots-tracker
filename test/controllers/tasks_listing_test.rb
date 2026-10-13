require "test_helper"

# The manager's task list: paging, the extra filters, the breakdown tables and
# the PDF report.
class TasksListingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    sign_in @manager
    TaskWorkSession.delete_all
    TaskComment.delete_all
    Task.delete_all
  end

  def make(title, **attrs)
    Task.create!({ title: title, priority: "normal", assigned_to: users(:exec_web_a), assigned_by: @manager,
                   task_type: task_types(:web_build) }.merge(attrs))
  end

  def row_titles
    css_select("#tm-region-tasks .tm-table tbody tr[data-task-id] .tm-task__title, #tm-region-tasks .tm-table tbody .tm-task__title").map { |n| n.text.squish }
  end

  test "the list shows one page of tasks and says how many there are" do
    25.times { |i| make(format("Task %02d", i)) }

    get dashboard_tasks_path

    assert_response :success
    assert_select "#tm-region-tasks .tm-pager", text: /1.+20 of 25/m
    assert_select "#tm-region-tasks .tm-table tbody tr", count: 20
  end

  test "the second page shows the rest" do
    25.times { |i| make(format("Task %02d", i)) }

    get dashboard_tasks_path(page: 2)

    assert_select "#tm-region-tasks .tm-table tbody tr", count: 5
  end

  test "a page past the end falls back to the last page instead of an empty list" do
    25.times { |i| make(format("Task %02d", i)) }

    get dashboard_tasks_path(page: 9)

    assert_select "#tm-region-tasks .tm-table tbody tr", count: 5
  end

  test "the page size can be changed" do
    25.times { |i| make(format("Task %02d", i)) }

    get dashboard_tasks_path(per: 50)

    assert_select "#tm-region-tasks .tm-table tbody tr", count: 25
  end

  test "no pager is shown when everything fits on one page" do
    3.times { |i| make("Task #{i}") }

    get dashboard_tasks_path

    assert_select "#tm-region-tasks .tm-pager__pages", count: 0
  end

  test "tasks can be filtered by client" do
    make("For the client", sprint: sprints(:crm_week_one))
    make("Internal")

    get dashboard_tasks_path(client_id: clients(:gnexteriors).id)

    assert_includes response.body, "For the client"
    assert_select "#tm-region-tasks .tm-table tbody tr", count: 1
  end

  test "tasks can be filtered by priority" do
    make("Urgent one", priority: "urgent")
    make("Normal one")

    get dashboard_tasks_path(priority: "urgent")

    assert_select "#tm-region-tasks .tm-table tbody tr", count: 1
  end

  test "tasks can be filtered by task type" do
    make("Typed")

    get dashboard_tasks_path(task_type_id: task_types(:web_build).id)
    assert_select "#tm-region-tasks .tm-table tbody tr", count: 1

    get dashboard_tasks_path(task_type_id: 0)
    assert_select "#tm-region-tasks .tm-table tbody tr", count: 0
  end

  test "the dashboard lists every executive's task totals and every client's" do
    make("Client task", sprint: sprints(:crm_week_one))

    get dashboard_tasks_path

    assert_select "#tm-region-breakdown .tm-breakdown--executives tbody tr", minimum: 1
    assert_select "#tm-region-breakdown .tm-breakdown--executives", text: /#{users(:exec_web_a).name}/
    assert_select "#tm-region-breakdown .tm-breakdown--clients", text: /GN Exteriors/
  end

  test "the report downloads as a PDF" do
    make("In the report", sprint: sprints(:crm_week_one))

    get export_tasks_path(report: "summary", format: :pdf)

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
  end

  test "the PDF report is refused for someone without the task manager permission" do
    sign_out @manager
    sign_in users(:exec_web_a)

    get export_tasks_path(report: "summary", format: :pdf)

    assert_response :redirect
  end
end

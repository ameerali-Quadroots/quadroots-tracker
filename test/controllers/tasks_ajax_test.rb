require "test_helper"

# The regions envelope is the contract between TasksController and
# task_manager.js: every mutation answers with re-rendered HTML keyed by the
# CSS selector it belongs at. If this shape changes, the whole module's client
# side stops updating, so it is pinned here.
class TasksAjaxTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    @executive = users(:exec_web_a)
    @task = tasks(:pending_a)
  end

  def ajax_headers
    { "X-Requested-With" => "XMLHttpRequest" }
  end

  def envelope
    JSON.parse(response.body)
  end

  # --- the shape ---

  test "an ajax dashboard request returns regions keyed by selector" do
    sign_in @manager
    get dashboard_tasks_path, headers: ajax_headers

    assert_response :success
    assert envelope["ok"]
    assert_equal %w[#tm-region-summary #tm-region-charts #tm-region-tasks
                    #tm-region-team-hours #tm-region-sprints].sort,
                 envelope["regions"].keys.sort
  end

  test "a request can ask for only the regions it needs" do
    sign_in @manager
    get dashboard_tasks_path(regions: "tasks"), headers: ajax_headers

    assert_response :success
    assert_equal ["#tm-region-tasks"], envelope["regions"].keys
  end

  test "an ajax my-tasks request returns the executive's own regions" do
    sign_in @executive
    get my_tasks_tasks_path, headers: ajax_headers

    assert_response :success
    assert_equal %w[#tm-region-focus #tm-region-summary #tm-region-tasks].sort,
                 envelope["regions"].keys.sort
  end

  test "a plain request still renders the full page" do
    sign_in @manager
    get dashboard_tasks_path

    assert_response :success
    assert_select ".tm[data-tm-view=dashboard]"
    assert_select "#tm-region-tasks"
  end

  # --- mutations answer with fresh regions ---

  test "creating a task returns the re-rendered list containing it" do
    sign_in @manager

    assert_difference -> { Task.count }, 1 do
      post tasks_path, headers: ajax_headers, params: {
        task: { title: "Ship the invoice page", priority: "normal",
                assigned_to_id: @executive.id, task_type_id: task_types(:web_build).id }
      }
    end

    assert_response :success
    assert_includes envelope["message"], "Ship the invoice page"
    assert_includes envelope["regions"]["#tm-region-tasks"], "Ship the invoice page"
  end

  test "a rejected task returns an error and no regions" do
    sign_in @manager

    assert_no_difference -> { Task.count } do
      post tasks_path, headers: ajax_headers, params: {
        task: { title: "", priority: "normal", assigned_to_id: @executive.id,
                task_type_id: task_types(:web_build).id }
      }
    end

    assert_response :unprocessable_entity
    assert_not envelope["ok"]
    assert_includes envelope["error"], "Title"
    assert_nil envelope["regions"]
  end

  test "deleting a task returns a list that no longer holds it" do
    sign_in @manager
    title = @task.title

    delete task_path(@task), headers: ajax_headers

    assert_response :success
    assert_includes envelope["message"], title
    assert_not_includes envelope["regions"]["#tm-region-tasks"], title
  end

  test "starting a task returns the executive's own regions, not the manager's" do
    sign_in @executive

    post start_task_path(@task), headers: ajax_headers

    assert_response :success
    assert_equal "in_progress", @task.reload.status
    assert_includes envelope["regions"].keys, "#tm-region-focus"
    assert_not_includes envelope["regions"].keys, "#tm-region-team-hours"
  end

  test "the one-task-at-a-time rule comes back as an error, not a redirect" do
    sign_in @executive
    @task.start!
    other = Task.create!(title: "Second job", priority: "normal", assigned_to: @executive,
                         assigned_by: @manager, task_type: task_types(:web_build))

    post start_task_path(other), headers: ajax_headers

    assert_response :unprocessable_entity
    assert_includes envelope["error"], "Finish or pause"
    assert_equal "pending", other.reload.status
  end

  test "pausing carries the reason through" do
    sign_in @executive
    @task.start!

    post pause_task_path(@task), headers: ajax_headers, params: { reason: "Waiting on copy" }

    assert_response :success
    assert_equal "paused", @task.reload.status
    assert_equal "Waiting on copy", @task.reason
  end

  test "completing a task reports it and stops the timer" do
    sign_in @executive
    @task.start!

    post complete_task_path(@task), headers: ajax_headers

    assert_response :success
    assert_equal "completed", @task.reload.status
    assert_includes envelope["message"], "Completed"
  end

  # --- authorization is unchanged by the ajax path ---

  test "an executive cannot delete a task over ajax either" do
    sign_in @executive

    assert_no_difference -> { Task.count } do
      delete task_path(@task), headers: ajax_headers
    end

    assert_redirected_to root_path
  end

  test "an executive cannot reach the manager dashboard over ajax" do
    sign_in @executive
    get dashboard_tasks_path, headers: ajax_headers

    assert_redirected_to root_path
  end

  # fetch() follows a redirect transparently, so answering a background request
  # with one would hand the caller 200 OK carrying the dashboard page — which
  # the drawer would then render as if it were the task.
  test "opening a task you may not see is refused, never redirected" do
    sign_in users(:exec_web_b)

    get task_path(@task), headers: ajax_headers

    assert_response :forbidden
    assert_includes JSON.parse(response.body)["error"], "not authorized"
  end

  test "commenting on a task you may not see is refused the same way" do
    sign_in users(:exec_web_b)

    post task_comments_path(@task), headers: ajax_headers,
         params: { task_comment: { body: "Should not land" } }

    assert_response :forbidden
  end

  # --- filters ---

  test "the search filter narrows the rendered list" do
    sign_in @manager
    Task.create!(title: "Completely unrelated", priority: "normal", assigned_to: @executive,
                 assigned_by: @manager, task_type: task_types(:web_build))

    get dashboard_tasks_path(q: "unrelated", regions: "tasks"), headers: ajax_headers

    html = envelope["regions"]["#tm-region-tasks"]
    assert_includes html, "Completely unrelated"
    assert_not_includes html, @task.title
  end

  test "the over-budget filter finds a task that has run past its SLA" do
    sign_in @manager
    quick = TaskType.create!(name: "Quick turnaround", department: departments(:web), sla_minutes: 1)
    breached = Task.create!(title: "Ran long", priority: "normal", assigned_to: @executive,
                            assigned_by: @manager, task_type: quick)
    travel_to(3.hours.ago) { breached.start! }

    get dashboard_tasks_path(over: "1", regions: "tasks"), headers: ajax_headers

    html = envelope["regions"]["#tm-region-tasks"]
    assert_includes html, "Ran long"
    assert_not_includes html, @task.title
  end

  test "the executive's scope filter separates open work from finished work" do
    sign_in @executive
    done = Task.create!(title: "Already finished", priority: "normal", assigned_to: @executive,
                        assigned_by: @manager, task_type: task_types(:web_build))
    done.start!
    done.complete!

    get my_tasks_tasks_path(scope: "open", regions: "tasks"), headers: ajax_headers
    assert_not_includes envelope["regions"]["#tm-region-tasks"], "Already finished"

    get my_tasks_tasks_path(scope: "completed", regions: "tasks"), headers: ajax_headers
    assert_includes envelope["regions"]["#tm-region-tasks"], "Already finished"
  end
end

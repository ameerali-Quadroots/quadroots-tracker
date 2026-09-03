require "test_helper"

# Dragging a card between board columns. The board is a view onto the same
# timer state machine the executive drives, so a move has to run the real
# lifecycle call — and refuse, with a reason, where that call would not apply.
class TasksBoardMoveTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    @executive = users(:exec_web_a)
    @task = tasks(:pending_a)
    sign_in @manager
  end

  def ajax_headers = { "X-Requested-With" => "XMLHttpRequest" }
  def envelope = JSON.parse(response.body)

  def move(task, status, **params)
    patch move_task_path(task), headers: ajax_headers, params: { status: status }.merge(params)
  end

  test "moving a not-started card into Running starts its timer" do
    move(@task, "in_progress")

    assert_response :success
    assert_equal "in_progress", @task.reload.status
    assert @task.started_at.present?, "the clock should be running"
    assert_equal 1, @task.work_sessions.count
  end

  test "moving a running card into Paused stops the clock" do
    @task.start!

    move(@task, "paused")

    assert_response :success
    assert_equal "paused", @task.reload.status
    assert @task.work_sessions.last.ended_at.present?, "the session should be closed"
  end

  test "moving a paused card back into Running resumes it" do
    @task.start!
    @task.pause!

    move(@task, "in_progress")

    assert_response :success
    assert_equal "in_progress", @task.reload.status
  end

  test "moving a card into Done completes it and records the total" do
    @task.start!

    move(@task, "completed")

    assert_response :success
    assert_equal "completed", @task.reload.status
    assert @task.ended_at.present?
  end

  # The one-task-at-a-time rule belongs to the executive, not to the manager
  # doing the dragging, so the board has to honour it too.
  test "a card cannot be started while its executive is already running something" do
    other = Task.create!(title: "Already running", priority: "normal", assigned_to: @executive,
                         assigned_by: @manager, task_type: task_types(:web_build))
    other.start!

    move(@task, "in_progress")

    assert_response :unprocessable_entity
    assert_equal "pending", @task.reload.status
    assert_includes envelope["error"], "Already running"
  end

  test "a card that was never started cannot be dropped straight into Done" do
    move(@task, "completed")

    assert_response :unprocessable_entity
    assert_equal "pending", @task.reload.status
    assert_includes envelope["error"], "Start it before"
  end

  test "a card that was never started cannot be paused" do
    move(@task, "paused")

    assert_response :unprocessable_entity
    assert_includes envelope["error"], "nothing to pause"
  end

  # Rewinding would have to throw away or silently keep logged hours, and
  # either answer misreports the sprint.
  test "a started card cannot be dragged back to Not started" do
    @task.start!

    move(@task, "pending")

    assert_response :unprocessable_entity
    assert_equal "in_progress", @task.reload.status
    assert_includes envelope["error"], "can't go back"
  end

  test "dropping a card back in its own column is a no-op, not an error" do
    move(@task, "pending")

    assert_response :success
    assert_includes envelope["message"], "already there"
  end

  test "an unknown column is refused" do
    move(@task, "archived")

    assert_response :unprocessable_entity
    assert_includes envelope["error"], "isn't a column"
  end

  test "a move made from a sprint board answers with the board, not the dashboard" do
    sprint = sprints(:crm_week_one)
    @task.update!(sprint: sprint)

    move(@task, "in_progress", sprint_id: sprint.id)

    assert_response :success
    assert_equal %w[#tm-region-summary #tm-region-board #tm-region-people].sort,
                 envelope["regions"].keys.sort
    assert_includes envelope["regions"]["#tm-region-board"], @task.title
  end

  test "a manager cannot move a task in another department" do
    design_manager = User.create!(email: "dm.board@example.com", password: "password123", name: "DM",
                                  role_id: roles(:manager).id, department_id: departments(:design).id,
                                  employeed: true)
    other = Task.create!(title: "Not yours", priority: "normal", assigned_to: users(:exec_design),
                         assigned_by: design_manager,
                         task_type: TaskType.create!(name: "DX board", department: departments(:design), sla_minutes: 5))

    move(other, "in_progress")

    assert_response :forbidden
    assert_equal "pending", other.reload.status
  end

  test "an executive cannot move cards on the board" do
    sign_in @executive

    move(@task, "in_progress")

    assert_redirected_to root_path
    assert_equal "pending", @task.reload.status
  end
end

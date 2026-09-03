require "test_helper"

class TaskCommentsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    @executive = users(:exec_web_a)
    @task = tasks(:pending_a)
  end

  def ajax_headers
    { "X-Requested-With" => "XMLHttpRequest" }
  end

  # --- who may talk on a task ---

  test "the executive the task belongs to can comment on it" do
    sign_in @executive

    assert_difference -> { @task.comments.count }, 1 do
      post task_comments_path(@task), params: { task_comment: { body: "Starting this now." } },
           headers: ajax_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 1, body["count"]
    assert_includes body["html"], "Starting this now."
  end

  test "a manager in the same department can comment on any task in it" do
    sign_in @manager

    assert_difference -> { @task.comments.count }, 1 do
      post task_comments_path(@task), params: { task_comment: { body: "Please prioritise this." } },
           headers: ajax_headers
    end

    assert_response :created
  end

  test "an executive cannot comment on a task that is not theirs" do
    sign_in users(:exec_web_b)

    assert_no_difference -> { @task.comments.count } do
      post task_comments_path(@task), params: { task_comment: { body: "Sneaking in" } },
           headers: ajax_headers
    end

    assert_response :forbidden
  end

  test "a manager from another department cannot comment" do
    design_manager = User.create!(email: "dm.comments@example.com", password: "password123",
                                  name: "Design Manager", role_id: roles(:manager).id,
                                  department_id: departments(:design).id, employeed: true)
    sign_in design_manager

    assert_no_difference -> { @task.comments.count } do
      post task_comments_path(@task), params: { task_comment: { body: "Not my department" } },
           headers: ajax_headers
    end

    assert_response :forbidden
  end

  # --- validation ---

  test "an empty comment is refused with a readable message" do
    sign_in @executive

    assert_no_difference -> { @task.comments.count } do
      post task_comments_path(@task), params: { task_comment: { body: "   " } },
           headers: ajax_headers
    end

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "Comment cannot be empty"
  end

  test "a comment longer than the limit is refused" do
    sign_in @executive

    assert_no_difference -> { @task.comments.count } do
      post task_comments_path(@task),
           params: { task_comment: { body: "x" * (TaskComment::MAX_LENGTH + 1) } },
           headers: ajax_headers
    end

    assert_response :unprocessable_entity
  end

  # --- editing and deleting ---

  test "the author can edit their own comment inside the edit window" do
    sign_in @executive
    comment = @task.comments.create!(user: @executive, body: "Frist draft")

    patch task_comment_path(@task, comment), params: { task_comment: { body: "First draft" } },
          headers: ajax_headers

    assert_response :success
    assert_equal "First draft", comment.reload.body
  end

  test "a comment can no longer be edited once the window has passed" do
    sign_in @executive
    comment = nil
    travel_to(30.minutes.ago) { comment = @task.comments.create!(user: @executive, body: "Old news") }

    patch task_comment_path(@task, comment), params: { task_comment: { body: "Rewriting history" } },
          headers: ajax_headers

    assert_response :forbidden
    assert_equal "Old news", comment.reload.body
  end

  test "nobody can edit somebody else's comment" do
    comment = @task.comments.create!(user: @executive, body: "Mine")
    sign_in @manager

    patch task_comment_path(@task, comment), params: { task_comment: { body: "Not yours" } },
          headers: ajax_headers

    assert_response :forbidden
    assert_equal "Mine", comment.reload.body
  end

  test "the author can delete their own comment" do
    sign_in @executive
    comment = @task.comments.create!(user: @executive, body: "Never mind")

    assert_difference -> { @task.comments.count }, -1 do
      delete task_comment_path(@task, comment), headers: ajax_headers
    end

    assert_response :success
    assert_equal 0, JSON.parse(response.body)["count"]
  end

  test "a manager cannot delete an executive's comment" do
    comment = @task.comments.create!(user: @executive, body: "Standing by this")
    sign_in @manager

    assert_no_difference -> { @task.comments.count } do
      delete task_comment_path(@task, comment), headers: ajax_headers
    end

    assert_response :forbidden
  end

  # --- reading ---

  test "the thread comes back in the order it was written" do
    sign_in @executive
    travel_to(2.hours.ago) { @task.comments.create!(user: @executive, body: "Earlier note") }
    @task.comments.create!(user: @manager, body: "Later reply")

    get task_comments_path(@task), headers: ajax_headers

    assert_response :success
    html = JSON.parse(response.body)["html"]
    assert_operator html.index("Earlier note"), :<, html.index("Later reply")
  end

  # --- the counter the task list reads ---

  test "the task's comment count tracks the thread" do
    sign_in @executive

    post task_comments_path(@task), params: { task_comment: { body: "One" } }, headers: ajax_headers
    post task_comments_path(@task), params: { task_comment: { body: "Two" } }, headers: ajax_headers

    assert_equal 2, @task.reload.comments_count

    delete task_comment_path(@task, @task.comments.last), headers: ajax_headers
    assert_equal 1, @task.reload.comments_count
  end

  test "comments are shown in the task drawer" do
    sign_in @manager
    @task.comments.create!(user: @executive, body: "Blocked on client assets")

    get task_path(@task), headers: ajax_headers

    assert_response :success
    assert_includes response.body, "Blocked on client assets"
  end

  test "deleting a task takes its comments with it" do
    @task.comments.create!(user: @executive, body: "Goes away too")

    assert_difference -> { TaskComment.count }, -1 do
      @task.destroy
    end
  end
end

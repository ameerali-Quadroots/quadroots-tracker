require "test_helper"

class TasksMyTasksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:exec_web_a) }

  test "a subtask of my own task renders nested under it, not as a sibling" do
    Task.create!(title: "Nested child", priority: "normal", parent: tasks(:pending_a),
                 assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                 task_type: task_types(:web_build))

    get my_tasks_tasks_path

    assert_response :success
    assert_equal 2, css_select(".tm-item").size, "parent and child should both render"
    assert_equal 1, css_select(".tm-item--sub").size, "the child should be nested"
    assert_equal 1, response.body.scan("Nested child").size, "and rendered exactly once"
  end

  test "a subtask keeps its own timer controls" do
    child = Task.create!(title: "Nested child", priority: "normal", parent: tasks(:pending_a),
                         assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                         task_type: task_types(:web_build))

    get my_tasks_tasks_path

    assert_select ".tm-item--sub [data-tm-action=?]", start_task_path(child)
  end

  test "a subtask whose parent belongs to another executive still appears" do
    parent = Task.create!(title: "Someone elses parent", priority: "normal",
                          assigned_to: users(:exec_web_b), assigned_by: users(:manager_web),
                          task_type: task_types(:web_build))
    Task.create!(title: "Orphan-looking child", priority: "normal", parent: parent,
                 assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                 task_type: task_types(:web_build))

    get my_tasks_tasks_path

    assert_includes response.body, "Orphan-looking child"
    refute_includes response.body, "Someone elses parent"
  end
end

require "test_helper"

class TaskAssignmentScopeTest < ActiveSupport::TestCase
  def build_task(assigned_to:)
    Task.new(title: "T", priority: "normal", assigned_to: assigned_to,
             assigned_by: users(:manager_web), task_type: task_types(:web_build))
  end

  test "assigning to a direct report in the department is valid" do
    assert build_task(assigned_to: users(:exec_web_a)).valid?
  end

  test "assigning to a department executive who is not a direct report is valid" do
    task = build_task(assigned_to: users(:exec_web_b))

    assert task.valid?, task.errors.full_messages.to_sentence
  end

  test "assigning to an executive in another department is invalid" do
    task = build_task(assigned_to: users(:exec_design))

    refute task.valid?
    assert_includes task.errors[:assigned_to], "must be an Executive in your department"
  end

  test "assigning to a non-executive is invalid" do
    task = build_task(assigned_to: users(:manager_web))

    refute task.valid?
    assert_includes task.errors[:assigned_to], "must hold the Executive role"
  end
end

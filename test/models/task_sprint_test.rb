require "test_helper"

class TaskSprintTest < ActiveSupport::TestCase
  setup { @sprint = sprints(:crm_week_one) }

  def build_task(**overrides)
    Task.new({ title: "T", priority: "normal", assigned_to: users(:exec_web_a),
               assigned_by: users(:manager_web), task_type: task_types(:web_build) }.merge(overrides))
  end

  test "a task can belong to a sprint in its own department" do
    task = build_task(sprint: @sprint)

    assert task.save, task.errors.full_messages.to_sentence
    assert_equal @sprint, task.sprint
  end

  test "a task cannot belong to another department's sprint" do
    design_client = Client.create!(name: "Other", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")
    foreign = Sprint.create!(project: design_project, name: "W1",
                             start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    task = build_task(sprint: foreign)

    refute task.valid?
    assert_includes task.errors[:sprint], "must belong to your department"
  end

  test "a subtask inherits its parent's sprint on save" do
    parent = build_task(sprint: @sprint)
    parent.save!

    child = build_task(parent: parent, title: "Child")
    child.save!

    assert_equal @sprint.id, child.sprint_id
  end

  test "a subtask's sprint follows the parent even if set to something else" do
    parent = build_task(sprint: @sprint)
    parent.save!
    other = Sprint.create!(project: projects(:crm), name: "Week 2",
                           start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 14))

    child = build_task(parent: parent, sprint: other, title: "Child")
    child.save!

    assert_equal @sprint.id, child.sprint_id
  end

  test "in_sprint scope filters by sprint" do
    build_task(sprint: @sprint).save!
    build_task(title: "No sprint").save!

    assert_equal 1, Task.in_sprint(@sprint.id).count
  end
end

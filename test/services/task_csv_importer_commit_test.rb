require "test_helper"

class TaskCsvImporterCommitTest < ActiveSupport::TestCase
  setup do
    @manager = users(:manager_web)
    @sprint = sprints(:crm_week_one)
  end

  def importer(csv, **opts)
    TaskCsvImporter.new(csv_text: csv, manager: @manager, sprint: @sprint, **opts)
  end

  test "commit creates tasks and links subtasks to their parent" do
    csv = file_fixture("sprint_tasks.csv").read

    assert_difference -> { Task.count }, 3 do
      assert_equal 3, importer(csv).commit!
    end

    parent = Task.find_by(title: "Build login")
    child = Task.find_by(title: "Password reset")
    assert_equal parent.id, child.parent_id
    assert_equal users(:exec_web_b).id, child.assigned_to_id
    assert_equal @sprint.id, parent.sprint_id
    assert_equal @sprint.id, child.sprint_id
    assert_equal @manager.id, parent.assigned_by_id
    assert_equal "urgent", parent.priority
    assert_equal 180, parent.custom_sla_minutes
  end

  test "commit resolves a parent that appears after its child" do
    csv = <<~CSV
      Key,Title,Parent,Assignee Email,Task Type
      T2,Child first,T1,exec.web.a@example.com,Build
      T1,Parent second,,exec.web.a@example.com,Build
    CSV

    importer(csv).commit!

    assert_equal Task.find_by(title: "Parent second").id,
                 Task.find_by(title: "Child first").parent_id
  end

  test "commit writes nothing when any row is invalid" do
    csv = <<~CSV
      Key,Title,Assignee Email,Task Type
      T1,Good row,exec.web.a@example.com,Build
      T2,Bad row,exec.design@example.com,Build
    CSV

    assert_no_difference -> { Task.count } do
      assert_equal 0, importer(csv).commit!
    end
  end

  test "commit creates a missing task type when allowed" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,X,exec.web.a@example.com,Brand New Type\n"

    assert_difference -> { TaskType.count }, 1 do
      importer(csv, create_missing_types: true).commit!
    end

    assert_equal departments(:web).id, TaskType.find_by(name: "Brand New Type").department_id
  end
end

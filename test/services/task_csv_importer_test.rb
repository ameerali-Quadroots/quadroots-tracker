require "test_helper"

class TaskCsvImporterTest < ActiveSupport::TestCase
  setup do
    @manager = users(:manager_web)
    @sprint = sprints(:crm_week_one)
  end

  def importer(csv, **opts)
    TaskCsvImporter.new(csv_text: csv, manager: @manager, sprint: @sprint, **opts)
  end

  def valid_csv = file_fixture("sprint_tasks.csv").read

  test "parses every data row" do
    result = importer(valid_csv)

    assert_equal 3, result.rows.size
    assert result.valid?, result.rows.flat_map(&:errors).inspect
  end

  test "resolves a parent by its Key" do
    result = importer(valid_csv)

    child = result.rows.find { |r| r.key == "T2" }
    assert_equal "T1", child.parent_key
  end

  test "rejects an assignee outside the manager's department" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,X,exec.design@example.com,Build\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "not an Executive in your department"
  end

  test "rejects an unknown task type unless creation is allowed" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,X,exec.web.a@example.com,Nonexistent\n"

    refute importer(csv).valid?
    assert importer(csv, create_missing_types: true).valid?
  end

  test "rejects a parent key that no row defines" do
    csv = "Key,Title,Parent,Assignee Email,Task Type\nT1,X,GHOST,exec.web.a@example.com,Build\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "no row defines parent key"
  end

  test "rejects a subtask whose parent is itself a subtask" do
    csv = <<~CSV
      Key,Title,Parent,Assignee Email,Task Type
      T1,Top,,exec.web.a@example.com,Build
      T2,Child,T1,exec.web.a@example.com,Build
      T3,Grandchild,T2,exec.web.a@example.com,Build
    CSV

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.last.errors.join, "only one level of subtasks"
  end

  test "rejects a missing title" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,,exec.web.a@example.com,Build\n"

    refute importer(csv).valid?
  end

  test "rejects an invalid priority" do
    csv = "Key,Title,Assignee Email,Task Type,Priority\nT1,X,exec.web.a@example.com,Build,critical\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "priority must be"
  end

  test "accepts both date formats and a blank date" do
    csv = <<~CSV
      Key,Title,Assignee Email,Task Type,Due Date
      T1,A,exec.web.a@example.com,Build,2026-09-05
      T2,B,exec.web.a@example.com,Build,06/09/2026
      T3,C,exec.web.a@example.com,Build,
    CSV

    result = importer(csv)

    assert result.valid?, result.rows.flat_map(&:errors).inspect
    assert_equal Date.new(2026, 9, 5), result.rows[0].due_date
    assert_equal Date.new(2026, 9, 6), result.rows[1].due_date
    assert_nil result.rows[2].due_date
  end

  test "rejects a file over the row cap" do
    body = (1..1001).map { |i| "T#{i},Task #{i},exec.web.a@example.com,Build" }.join("\n")
    csv = "Key,Title,Assignee Email,Task Type\n#{body}\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "1000 rows"
  end

  test "rejects a file missing the Title column" do
    csv = "Key,Assignee Email,Task Type\nT1,exec.web.a@example.com,Build\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "Title"
  end
end

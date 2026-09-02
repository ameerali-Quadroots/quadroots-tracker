require "test_helper"

class TasksImportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  def upload
    Rack::Test::UploadedFile.new(file_fixture("sprint_tasks.csv"), "text/csv")
  end

  test "preview reports the rows without creating anything" do
    assert_no_difference -> { Task.count } do
      post import_preview_tasks_path, params: { file: upload, sprint_id: sprints(:crm_week_one).id }
    end

    assert_response :success
    assert_includes response.body, "Build login"
  end

  test "import creates the tasks" do
    assert_difference -> { Task.count }, 3 do
      post import_tasks_path, params: { file: upload, sprint_id: sprints(:crm_week_one).id }
    end

    assert_redirected_to dashboard_tasks_path(tab: "tasks")
  end

  test "import refuses a sprint from another department" do
    design_client = Client.create!(name: "Other", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")
    foreign = Sprint.create!(project: design_project, name: "W1",
                             start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    assert_no_difference -> { Task.count } do
      post import_tasks_path, params: { file: upload, sprint_id: foreign.id }
    end

    assert_equal "That sprint doesn't belong to your department.", flash[:alert]
  end

  test "import rejects a missing file" do
    post import_tasks_path, params: { sprint_id: sprints(:crm_week_one).id }

    assert_redirected_to dashboard_tasks_path(tab: "tasks")
    assert_equal "Choose a CSV file to import.", flash[:alert]
  end
end

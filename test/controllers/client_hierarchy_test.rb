require "test_helper"

# Client -> project -> sprint as browsable pages, so every step of a sprint's
# breadcrumb leads somewhere instead of being a dead label.
class ClientHierarchyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    @client = clients(:gnexteriors)
    @project = projects(:crm)
    @sprint = sprints(:crm_week_one)
    sign_in @manager
  end

  test "the clients index lists the department's clients" do
    get clients_path

    assert_response :success
    assert_select ".tm-tile", minimum: 1
    assert_includes response.body, @client.name
  end

  test "the clients index hides another department's clients" do
    other = Client.create!(name: "Design Only Client", department: departments(:design))

    get clients_path

    assert_response :success
    assert_not_includes response.body, other.name
  end

  test "a client page lists its projects" do
    get client_path(@client)

    assert_response :success
    assert_includes response.body, @project.name
  end

  test "a client in another department cannot be opened" do
    other = Client.create!(name: "Not Yours", department: departments(:design))

    get client_path(other)

    assert_redirected_to clients_path
  end

  test "a project page lists its sprints" do
    get project_path(@project)

    assert_response :success
    assert_includes response.body, @sprint.name
    assert_select "a[href=?]", sprint_path(@sprint)
  end

  test "a project in another department cannot be opened" do
    other_client = Client.create!(name: "Elsewhere", department: departments(:design))
    other_project = other_client.projects.create!(name: "Elsewhere CRM")

    get project_path(other_project)

    assert_redirected_to clients_path
  end

  test "the sprints index groups every sprint by client" do
    get sprints_path

    assert_response :success
    assert_includes response.body, @sprint.name
    assert_includes response.body, @client.name
  end

  test "a sprint's breadcrumb links to its project and client" do
    get sprint_path(@sprint)

    assert_response :success
    assert_select ".tm-crumb a[href=?]", client_path(@client)
    assert_select ".tm-crumb a[href=?]", project_path(@project)
    assert_select ".tm-crumb a[href=?]", clients_path
  end

  # The counts on these pages come from grouped aggregates; a page that queried
  # per row would degrade as the department takes on more clients.
  test "the clients index does not query per client" do
    5.times { |i| Client.create!(name: "Bulk client #{i}", department: departments(:web)) }

    # Warm the first request: Rails resolves and caches a good deal of
    # machinery on the way through, and that one-off cost is not per-client.
    get clients_path
    baseline = count_queries { get clients_path }

    5.times { |i| Client.create!(name: "More clients #{i}", department: departments(:web)) }

    assert_equal baseline, count_queries { get clients_path },
                 "the clients index must not issue a query per client"
  end

  test "an executive cannot reach the client pages" do
    sign_in users(:exec_web_a)

    get clients_path
    assert_redirected_to root_path

    get client_path(@client)
    assert_redirected_to root_path

    get sprints_path
    assert_redirected_to root_path
  end

  def count_queries
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT")
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end

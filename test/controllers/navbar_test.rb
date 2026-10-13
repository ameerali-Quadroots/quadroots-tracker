require "test_helper"

# Pins what the top navigation offers each kind of user, so the navbar can be
# restructured without changing who sees which link.
class NavbarTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def nav_labels
    css_select(".app-navbar .app-nav > .nav-item > .nav-link").map { |a| a.text.squish.sub(/\s*\d+\z/, "") }
  end

  test "an executive sees their own pages but not the review queues" do
    sign_in users(:exec_web_a)
    get root_path

    assert_response :success
    assert_includes nav_labels, "Dashboard"
    assert_includes nav_labels, "My Requests"
    assert_includes nav_labels, "My Leaves"
    assert_not_includes nav_labels, "Edit Requests"
    assert_not_includes nav_labels, "Leave Requests"
  end

  test "the current page is marked active" do
    sign_in users(:exec_web_a)
    get root_path

    assert_select ".app-navbar .nav-link.active", text: /Dashboard/, count: 1
  end

  test "a manager with the task manager permission gets the Task Manager link" do
    sign_in users(:manager_web)
    get root_path

    assert_select ".app-navbar .dropdown-menu a[href=?]", dashboard_tasks_path, text: /Task Manager/
    assert_select ".app-navbar .dropdown-menu a[href=?]", my_tasks_tasks_path
  end

  test "an executive gets My Tasks but not the Task Manager link" do
    sign_in users(:exec_web_a)
    get root_path

    assert_select ".app-navbar .dropdown-menu a[href=?]", my_tasks_tasks_path
    assert_select ".app-navbar .dropdown-menu a[href=?]", dashboard_tasks_path, count: 0
  end

  test "someone in a department without the task manager has no Tasks menu" do
    users(:exec_web_a).update!(org_department: departments(:sales))
    sign_in users(:exec_web_a)
    get root_path

    assert_select ".app-navbar a[href=?]", my_tasks_tasks_path, count: 0
  end

  test "the account menu links to the profile and signs out" do
    sign_in users(:exec_web_a)
    get root_path

    assert_select ".app-navbar a[href=?]", edit_user_path(users(:exec_web_a))
    assert_select ".app-navbar form[action=?]", destroy_user_session_path
  end

  test "an open edit request shows as a count on My Requests" do
    user = users(:exec_web_a)
    sign_in user
    get root_path
    before = css_select(".app-navbar a[href='#{my_requests_edit_requests_path}'] .nav-badge").first&.text.to_i

    assert_equal user.edit_requests.count, before
  end
end

class HomeInsightsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:exec_web_a) }

  test "the home page shows this month's figures by default" do
    get root_path

    assert_response :success
    assert_select ".insights [aria-current=true]", text: /This month/
    assert_select ".insights-kpi", minimum: 4
  end

  test "the last-month filter switches the figures to the previous month" do
    get root_path(period: "last")

    assert_select ".insights [aria-current=true]", text: /Last month/
    assert_select ".insights-month", text: /#{Date.current.prev_month.strftime('%B %Y')}/
  end

  test "breaks are not shown when there is no open shift" do
    shift = TimeClock.create!(employee: users(:exec_web_a), status: "on_time", clock_in: 9.hours.ago, clock_out: 1.hour.ago)
    Break.create!(time_clock: shift, break_type: "Meeting", break_in: 5.hours.ago, break_out: 4.hours.ago)

    get root_path

    assert_select ".insights-breaks", count: 0
    assert_select ".breaks-section", count: 0
  end

  test "breaks of the open shift are listed in the monthly section, not under the summary" do
    shift = TimeClock.create!(employee: users(:exec_web_a), status: "on_time", clock_in: 3.hours.ago)
    Break.create!(time_clock: shift, break_type: "Meeting", break_in: 2.hours.ago, break_out: 90.minutes.ago)

    get root_path

    assert_select ".home-summary .breaks-section", count: 0
    assert_select ".insights .insights-breaks li", count: 1
    assert_select ".insights-breaks", text: /Meeting/
  end

  test "an open shift with no breaks yet shows no breaks card" do
    TimeClock.create!(employee: users(:exec_web_a), status: "on_time", clock_in: 3.hours.ago)

    get root_path

    assert_select ".insights-breaks", count: 0
  end

  test "during a break the headline shows a break timer instead of the working timer" do
    # Starting a break also sets the shift's state (BreaksController#break_in).
    shift = TimeClock.create!(employee: users(:exec_web_a), status: "on_time", clock_in: 3.hours.ago, current_state: "Meeting")
    Break.create!(time_clock: shift, break_type: "Meeting", break_in: 10.minutes.ago)

    get root_path

    assert_select "[data-break-timer][data-break-start]", count: 1
    assert_select "[data-live-timer]", count: 0
  end

  test "while working the headline shows the working timer and no break timer" do
    TimeClock.create!(employee: users(:exec_web_a), status: "on_time", clock_in: 3.hours.ago)

    get root_path

    assert_select "[data-live-timer]", count: 1
    assert_select "[data-break-timer]", count: 0
  end

  test "a shift clocked in after midnight is listed under the day it started" do
    travel_to Time.zone.local(2026, 9, 9, 2, 0) do
      TimeClock.create!(employee: users(:exec_web_a), status: "late", clock_in: Time.zone.local(2026, 9, 9, 0, 30))

      get root_path

      assert_select ".table-premium tbody td", text: /Tue, 08 Sep/
      assert_select ".table-premium tbody td", text: /Wed, 09 Sep/, count: 0
    end
  end

  test "the leave balance card is gone" do
    get root_path

    assert_select ".insights", text: /Leave balance/, count: 0
  end

  test "the page loader is part of the layout" do
    get root_path

    assert_select "#app-loader svg.qr-loader__icon"
  end
end

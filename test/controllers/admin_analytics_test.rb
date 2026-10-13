require "test_helper"

class AdminAnalyticsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Permission.sync_catalogue!
    @role = Role.create!(name: "HR Officer", scope: "admin", rank: 10)
    @admin = admin_users(:one)
    @admin.update!(access_role: @role, org_department: departments(:web))
    TimeClock.create!(employee: users(:exec_web_a), status: "late", total_duration: 8.hours.to_i,
                      clock_in: Time.zone.local(2026, 9, 2, 18, 30))
    TimeClock.create!(employee: users(:exec_design), status: "late", total_duration: 8.hours.to_i,
                      clock_in: Time.zone.local(2026, 9, 2, 18, 30))
    sign_in @admin
  end

  def grant
    @role.permissions << Permission.find_by!(key: "analytics.read")
  end

  test "an admin without the Analytics permission cannot open the page" do
    get admin_analytics_path

    assert_response :redirect
  end

  test "an admin with the Analytics permission sees the charts" do
    grant

    get admin_analytics_path(from: "2026-09-01", to: "2026-09-10")

    assert_response :success
    assert_select "[data-chart]", minimum: 4
    assert_select ".an-top-late", text: /Web Exec A/
  end

  test "a department-scoped admin does not see other departments" do
    grant

    get admin_analytics_path(from: "2026-09-01", to: "2026-09-10")

    assert_no_match "Design Exec", response.body
  end

  test "a preset period is accepted" do
    grant

    get admin_analytics_path(period: "90")

    assert_response :success
  end

  test "a nonsense date range falls back to the default period" do
    grant

    get admin_analytics_path(from: "not-a-date", to: "2026-13-45")

    assert_response :success
  end

  test "the Analytics permission appears in the role matrix catalogue" do
    assert_equal "Analytics", Permission.find_by!(key: "analytics.read").group
  end
end

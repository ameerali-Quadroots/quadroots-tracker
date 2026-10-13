require "test_helper"

class AdminShiftTimingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Permission.sync_catalogue!
    @role = Role.create!(name: "HR Officer", scope: "admin", rank: 10)
    @admin = admin_users(:one)
    @admin.update!(access_role: @role, org_department: departments(:web))

    sign_in @admin
  end

  def grant_employee_edit
    @role.permissions << Permission.find_by!(key: "user.update")
  end

  def shift_of(name)
    users(name).reload.shift_time.strftime("%H:%M")
  end

  test "an admin who cannot edit employees cannot open the page" do
    get admin_shift_timings_path

    assert_response :redirect
  end

  test "an admin who cannot edit employees cannot apply a change" do
    post admin_shift_timings_apply_path, params: { scope: "departments", department_ids: [departments(:web).id], shift_time: "20:00" }

    assert_response :redirect
    assert_equal "18:00", shift_of(:exec_web_a)
  end

  test "the page lists the current timings of the admin's departments only" do
    grant_employee_edit

    get admin_shift_timings_path

    assert_response :success
    assert_select "table.shift-timings-current", text: /Web/
    assert_select "table.shift-timings-current", text: /Design/, count: 0
    assert_select "input[name='department_ids[]']", count: 1
    assert_select "input[name='scope'][value='all']", count: 0
  end

  test "applying to a department changes its employees" do
    grant_employee_edit

    post admin_shift_timings_apply_path, params: { scope: "departments", department_ids: [departments(:web).id], shift_time: "20:00" }

    assert_redirected_to admin_shift_timings_path
    assert_match(/3 employees/, flash[:notice])
    assert_equal "20:00", shift_of(:exec_web_a)
    assert_equal "18:00", shift_of(:exec_design)
  end

  test "a department outside the admin's access is ignored" do
    grant_employee_edit

    post admin_shift_timings_apply_path, params: { scope: "departments", department_ids: [departments(:design).id], shift_time: "20:00" }

    assert_redirected_to admin_shift_timings_path
    assert flash[:alert].present?
    assert_equal "18:00", shift_of(:exec_design)
  end

  test "a department admin cannot apply to all employees" do
    grant_employee_edit

    post admin_shift_timings_apply_path, params: { scope: "all", shift_time: "20:00" }

    assert flash[:alert].present?
    assert_equal "18:00", shift_of(:exec_design)
    assert_equal "18:00", shift_of(:exec_web_a)
  end

  test "a super admin can apply to all employees" do
    @admin.update!(access_role: Role.create!(name: "Super Admin", scope: "admin", rank: 100, system: true))

    get admin_shift_timings_path
    assert_select "input[name='scope'][value='all']"

    post admin_shift_timings_apply_path, params: { scope: "all", shift_time: "20:00" }

    assert_match(/#{User.employed.count} employees/, flash[:notice])
    assert_equal "20:00", shift_of(:exec_design)
    assert_equal "20:00", shift_of(:one)
  end

  test "a bad time is refused" do
    grant_employee_edit

    post admin_shift_timings_apply_path, params: { scope: "departments", department_ids: [departments(:web).id], shift_time: "" }

    assert flash[:alert].present?
    assert_equal "18:00", shift_of(:exec_web_a)
  end
end

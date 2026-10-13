require "test_helper"

class AdminBulkCorrectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Permission.sync_catalogue!
    @role = Role.create!(name: "HR Officer", scope: "admin", rank: 10)
    @admin = admin_users(:one)
    @admin.update!(access_role: @role, org_department: departments(:web))

    @late_web    = TimeClock.create!(employee: users(:exec_web_a), status: "late", clock_in: Time.zone.local(2026, 9, 7, 18, 40))
    @late_design = TimeClock.create!(employee: users(:exec_design), status: "late", clock_in: Time.zone.local(2026, 9, 7, 18, 40))

    sign_in @admin
  end

  def grant_time_clock_edit
    @role.permissions << Permission.find_by!(key: "time_clock.update")
  end

  def make_super_admin
    @admin.update!(access_role: Role.create!(name: "Super Admin", scope: "admin", rank: 100, system: true))
  end

  def apply_params(extra = {})
    { date: "2026-09-07", scope: "departments", department_ids: [departments(:web).id],
      time_clock_ids: [@late_web.id], reason: "Server down" }.merge(extra)
  end

  test "an admin who cannot edit time clocks cannot open the page" do
    get admin_bulk_correction_path

    assert_response :redirect
  end

  test "an admin who cannot edit time clocks cannot apply" do
    post admin_bulk_correction_apply_path, params: apply_params

    assert_response :redirect
    assert_equal "late", @late_web.reload.status
  end

  test "the page lists late employees of the admin's departments for the day" do
    grant_time_clock_edit

    get admin_bulk_correction_path(date: "2026-09-07", scope: "departments", department_ids: [departments(:web).id])

    assert_response :success
    assert_select "table.bulk-correction-late tbody tr", count: 1
    assert_select "table.bulk-correction-late", text: /Web Exec A/
    assert_select "input[name='time_clock_ids[]'][value='#{@late_web.id}'][checked]"
    assert_select ".bulk-correction-missing", text: /Web Exec B/
  end

  test "applying removes the late mark and records the correction" do
    grant_time_clock_edit

    post admin_bulk_correction_apply_path, params: apply_params

    assert_response :redirect
    assert_match(/1 employee/, flash[:notice])
    assert_equal "on_time", @late_web.reload.status
    assert_equal @admin, BulkCorrection.last.admin_user
  end

  test "a shift outside the admin's departments is not corrected" do
    grant_time_clock_edit

    post admin_bulk_correction_apply_path,
         params: apply_params(department_ids: [departments(:design).id], time_clock_ids: [@late_design.id])

    assert flash[:alert].present?
    assert_equal "late", @late_design.reload.status
  end

  test "a department admin cannot correct all employees" do
    grant_time_clock_edit

    post admin_bulk_correction_apply_path, params: apply_params(scope: "all", time_clock_ids: [@late_web.id, @late_design.id])

    assert flash[:alert].present?
    assert_equal "late", @late_design.reload.status
    assert_equal "late", @late_web.reload.status
  end

  test "a super admin can correct all employees" do
    make_super_admin

    post admin_bulk_correction_apply_path, params: apply_params(scope: "all", time_clock_ids: [@late_web.id, @late_design.id])

    assert_match(/2 employees/, flash[:notice])
    assert_equal "on_time", @late_design.reload.status
  end

  test "a missing reason is refused" do
    grant_time_clock_edit

    post admin_bulk_correction_apply_path, params: apply_params(reason: "")

    assert flash[:alert].present?
    assert_equal "late", @late_web.reload.status
  end

  test "the admin can undo their own correction" do
    grant_time_clock_edit
    post admin_bulk_correction_apply_path, params: apply_params

    get admin_bulk_correction_path
    assert_select "table.bulk-correction-history", text: /Server down/

    post admin_bulk_correction_undo_path, params: { id: BulkCorrection.last.id }

    assert_match(/undone/i, flash[:notice])
    assert_equal "late", @late_web.reload.status
  end

  test "a department admin cannot undo someone else's correction" do
    grant_time_clock_edit
    log = TimeClocks::BulkCorrection.new(shift_date: Date.new(2026, 9, 7), departments: nil)
                                    .apply(time_clock_ids: [@late_design.id], reason: "Outage", admin: admin_users(:two)).record

    post admin_bulk_correction_undo_path, params: { id: log.id }

    assert flash[:alert].present?
    assert_equal "on_time", @late_design.reload.status
  end
end

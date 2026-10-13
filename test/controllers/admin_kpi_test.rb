require "test_helper"

class AdminKpiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Permission.sync_catalogue!
    @role = Role.create!(name: "HR Officer", scope: "admin", rank: 10)
    @admin = admin_users(:one)
    @admin.update!(access_role: @role, org_department: departments(:web))

    4.times do |i|
      TimeClock.create!(employee: users(:exec_web_a), status: "late",
                        clock_in: Time.zone.local(2026, 9, i + 1, 18, 30))
    end

    sign_in @admin
  end

  def employees_sheet
    # open_buffer returns the IO, not the block's value, so capture the sheet inside it.
    xml = nil
    Zip::File.open_buffer(StringIO.new(response.body)) { |zip| xml = zip.read("xl/worksheets/sheet2.xml") }
    xml
  end

  def grant_kpi
    @role.permissions << Permission.find_by!(key: "kpi.read")
  end

  test "an admin without the KPI permission cannot open the page" do
    get admin_kpi_path(month: "2026-09")

    assert_response :redirect
  end

  test "an admin without the KPI permission cannot export" do
    get admin_kpi_export_path(month: "2026-09")

    assert_response :redirect
  end

  test "an admin with the KPI permission sees flagged employees" do
    grant_kpi

    get admin_kpi_path(month: "2026-09")

    assert_response :success
    assert_select "tr.kpi-flagged", text: /Web Exec A/
  end

  test "only flagged employees are listed by default" do
    grant_kpi

    get admin_kpi_path(month: "2026-09")

    assert_select "table.kpi-employees tbody tr", count: 1
    assert_select "table.kpi-employees", text: /Web Exec B/, count: 0
  end

  test "the department summary still counts everyone when only flagged are listed" do
    grant_kpi

    get admin_kpi_path(month: "2026-09")

    assert_select "table.kpi-summary tbody tr td:nth-child(2)",
                  text: User.employed.where(department: "Web").count.to_s
  end

  test "choosing all employees lists the unflagged ones too" do
    grant_kpi

    get admin_kpi_path(month: "2026-09", show: "all")

    assert_select "table.kpi-employees", text: /Web Exec B/
  end

  test "the export lists only flagged employees by default" do
    grant_kpi

    get admin_kpi_export_path(month: "2026-09")

    assert_includes employees_sheet, "Web Exec A"
    assert_not_includes employees_sheet, "Web Exec B"
  end

  test "the export includes everyone when all employees are shown" do
    grant_kpi

    get admin_kpi_export_path(month: "2026-09", show: "all")

    assert_includes employees_sheet, "Web Exec B"
  end

  test "rows do not link to the employee for an admin who cannot view employees" do
    grant_kpi

    get admin_kpi_path(month: "2026-09")

    assert_select "table.kpi-employees tr[data-href]", count: 0
  end

  test "rows open the employee profile for an admin who can view employees" do
    grant_kpi
    @role.permissions << Permission.find_by!(key: "user.read")

    get admin_kpi_path(month: "2026-09")

    assert_select "table.kpi-employees tr[data-href=?]", "/admin/employees/#{users(:exec_web_a).id}"
  end

  test "a department-scoped admin does not see other departments" do
    grant_kpi

    get admin_kpi_path(month: "2026-09")

    assert_no_match "Design Exec", response.body
  end

  test "the export downloads an Excel workbook" do
    grant_kpi

    get admin_kpi_export_path(month: "2026-09")

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    assert response.body.start_with?("PK")
  end

  test "the KPI permission appears in the role matrix catalogue" do
    assert_equal "KPI", Permission.find_by!(key: "kpi.read").group
  end

  # ---- Sorting ---------------------------------------------------------------

  def employee_names
    css_select("table.kpi-employees tbody tr td:first-child").map { |cell| cell.text.squish }
  end

  def late(user, count)
    count.times do |i|
      TimeClock.create!(employee: user, status: "late", clock_in: Time.zone.local(2026, 9, 10 + i, 18, 30))
    end
  end

  test "employees can be sorted by name, A to Z and Z to A" do
    grant_kpi

    get admin_kpi_path(month: "2026-09", show: "all", sort: "name", dir: "asc")
    assert_equal employee_names.sort_by(&:downcase), employee_names

    get admin_kpi_path(month: "2026-09", show: "all", sort: "name", dir: "desc")
    assert_equal employee_names.sort_by(&:downcase).reverse, employee_names
  end

  test "a name stored with stray spaces still sorts by its letters" do
    grant_kpi
    # A leading space sorts before every letter, which would put this name first.
    users(:exec_web_b).update_columns(name: "  Zed Late")

    get admin_kpi_path(month: "2026-09", show: "all", sort: "name", dir: "asc")

    assert_equal "Zed Late", employee_names.last
  end

  test "employees can be sorted by lates, most first or fewest first" do
    grant_kpi
    late(users(:exec_web_b), 2)

    get admin_kpi_path(month: "2026-09", show: "all", sort: "lates", dir: "desc")
    assert_equal ["Web Exec A", "Web Exec B"], employee_names.first(2)

    get admin_kpi_path(month: "2026-09", show: "all", sort: "lates", dir: "asc")
    assert_equal "Web Exec A", employee_names.last
  end

  test "an unknown sort column falls back to the default order" do
    grant_kpi

    get admin_kpi_path(month: "2026-09", show: "all", sort: "drop table", dir: "sideways")

    assert_response :success
    assert_equal "Web Exec A", employee_names.first   # flagged employees first
  end

  test "column headers link to the sorted view and flip direction on the active column" do
    grant_kpi

    get admin_kpi_path(month: "2026-09", show: "all", sort: "lates", dir: "desc")

    assert_select "table.kpi-employees thead a[href*='sort=lates'][href*='dir=asc']"
    assert_select "table.kpi-employees thead a[href*='sort=name'][href*='dir=asc']"
    assert_select "table.kpi-employees thead th[aria-sort=descending]", text: /Lates/
  end

  test "the department summary can be sorted by lates" do
    grant_kpi
    @admin.additional_departments << departments(:design)
    late(users(:exec_design), 6)

    get admin_kpi_path(month: "2026-09", dsort: "lates", ddir: "desc")
    assert_equal "Design", css_select("table.kpi-summary tbody tr td:first-child").first.text.squish

    get admin_kpi_path(month: "2026-09", dsort: "department", ddir: "desc")
    assert_equal "Web", css_select("table.kpi-summary tbody tr td:first-child").first.text.squish
  end

  # ---- Pagination ------------------------------------------------------------

  def add_web_employees(count)
    count.times do |i|
      User.create!(email: "bulk#{i}@example.com", password: "password123", name: format("Bulk %02d", i),
                   role_id: roles(:executive).id, department_id: departments(:web).id, employeed: true)
    end
  end

  test "the employee list is paged and says how many there are" do
    grant_kpi
    add_web_employees(30)
    total = User.employed.where(department: "Web").count

    get admin_kpi_path(month: "2026-09", show: "all")

    assert_select "table.kpi-employees tbody tr", count: 25
    assert_select ".kpi-pager", text: /1 to 25 of #{total}/
  end

  test "the second page shows the rest and a page past the end shows the last page" do
    grant_kpi
    add_web_employees(30)
    rest = User.employed.where(department: "Web").count - 25

    get admin_kpi_path(month: "2026-09", show: "all", page: 2)
    assert_select "table.kpi-employees tbody tr", count: rest

    get admin_kpi_path(month: "2026-09", show: "all", page: 99)
    assert_select "table.kpi-employees tbody tr", count: rest
  end

  test "the page size can be changed" do
    grant_kpi
    add_web_employees(30)

    get admin_kpi_path(month: "2026-09", show: "all", per: 50)

    assert_select "table.kpi-employees tbody tr", count: User.employed.where(department: "Web").count
  end

  test "no page links are shown when everything fits on one page" do
    grant_kpi

    get admin_kpi_path(month: "2026-09", show: "all")

    assert_select ".kpi-pager a", count: 0
  end

  # ---- PDF -------------------------------------------------------------------

  test "the report downloads as a PDF" do
    grant_kpi

    get admin_kpi_export_path(month: "2026-09", as: "pdf")

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
  end

  test "an admin without the KPI permission cannot download the PDF" do
    get admin_kpi_export_path(month: "2026-09", as: "pdf")

    assert_response :redirect
  end

  test "the Excel export follows the chosen sort and is not cut to one page" do
    grant_kpi
    add_web_employees(30)

    get admin_kpi_export_path(month: "2026-09", show: "all", sort: "name", dir: "desc")

    assert_includes employees_sheet, "Bulk 00"
    assert_operator employees_sheet.index("Web Manager"), :<, employees_sheet.index("Bulk 00")
  end
end

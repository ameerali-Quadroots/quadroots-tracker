ActiveAdmin.register_page "KPI" do
  menu label: "KPI", priority: 6

  controller do
    helper_method :kpi_report, :kpi_month, :kpi_department_options, :kpi_show_all?, :kpi_employee_rows,
                  :kpi_summary_rows, :kpi_paging

    private

    # The month being viewed, from ?month=YYYY-MM (defaults to the current month).
    def kpi_month
      @kpi_month ||= begin
        Date.strptime(params[:month].to_s, "%Y-%m")
      rescue ArgumentError
        Time.zone.today.beginning_of_month
      end
    end

    # Departments this admin may pick from; same scoping as Time Clocks.
    def kpi_department_options
      @kpi_department_options ||=
        if current_admin_user.super_admin? || current_admin_user.qa_admin?
          User.employed.distinct.pluck(:department).compact_blank.sort
        else
          current_admin_user.viewable_department_names
        end
    end

    # Only flagged employees are listed unless ?show=all is chosen.
    def kpi_show_all?
      params[:show] == "all"
    end

    # Every employee in the current view, in the chosen order (?sort=name|department|lates,
    # ?dir=asc|desc). Not paged: the exports use this, the screen pages it.
    def kpi_employee_rows
      @kpi_employee_rows ||= Reports::LateKpi.sort(
        kpi_show_all? ? kpi_report.rows : kpi_report.flagged_rows,
        Reports::LateKpi::ROW_SORTS, params[:sort].to_s, params[:dir].to_s
      )
    end

    # The department summary, sorted by ?dsort=department|employees|lates|flagged.
    def kpi_summary_rows
      @kpi_summary_rows ||= Reports::LateKpi.sort(
        kpi_report.department_summary, Reports::LateKpi::SUMMARY_SORTS, params[:dsort].to_s, params[:ddir].to_s
      )
    end

    # One page of kpi_employee_rows. A page past the end shows the last page.
    def kpi_paging
      @kpi_paging ||= begin
        per   = [25, 50, 100].include?(params[:per].to_i) ? params[:per].to_i : 25
        total = kpi_employee_rows.size
        pages = [(total / per.to_f).ceil, 1].max
        page  = params[:page].to_i.clamp(1, pages)
        { per: per, total: total, pages: pages, page: page, rows: kpi_employee_rows[(page - 1) * per, per] || [] }
      end
    end

    def kpi_report
      @kpi_report ||= begin
        departments =
          if kpi_department_options.include?(params[:department])
            [params[:department]]
          elsif current_admin_user.super_admin? || current_admin_user.qa_admin?
            nil
          else
            kpi_department_options
          end

        Reports::LateKpi.new(month: kpi_month, departments: departments)
      end
    end
  end

  content title: "KPI" do
    render partial: "admin/kpi/report",
           locals: { report: kpi_report, month: kpi_month, department_options: kpi_department_options,
                     paging: kpi_paging, summary_rows: kpi_summary_rows, show_all: kpi_show_all?,
                     open_employees: authorized?(:read, User) }
  end

  # Export the month being viewed: XLSX by default, PDF with ?as=pdf. Both
  # follow the screen's filter and sort, and include every row, not one page.
  page_action :export, method: :get do
    report = kpi_report

    if params[:as] == "pdf"
      scope = [params[:department].presence || "All departments",
               kpi_show_all? ? "all employees" : "KPI deducted only"].join(", ")
      pdf = LateKpiPdf.new(report: report, summary_rows: kpi_summary_rows, employee_rows: kpi_employee_rows,
                           scope_label: scope, generated_by: current_admin_user.email)
      next send_data(pdf.render, filename: "late_kpi_#{kpi_month.strftime('%Y-%m')}.pdf",
                                 type: "application/pdf", disposition: "attachment")
    end

    require 'caxlsx'

    package  = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Department Summary") do |sheet|
      sheet.add_row ["Department", "Total Employees", "Total Lates", "KPI Deducted Employees"]
      kpi_summary_rows.each do |summary|
        sheet.add_row [summary.department, summary.total_employees, summary.total_lates, summary.flagged_count]
      end
      sheet.add_row ["Total",
                     report.rows.size,
                     report.rows.sum(&:late_count),
                     report.rows.count(&:kpi_deducted)]
    end

    workbook.add_worksheet(name: "Employees") do |sheet|
      sheet.add_row ["Employee", "Department", "Shift Time", "Lates", "Allowed Lates", "KPI Deducted"]
      kpi_employee_rows.each do |row|
        sheet.add_row [
          row.user.name,
          row.department,
          row.user.shift_time&.strftime("%I:%M %p"),
          row.late_count,
          report.limit,
          row.kpi_deducted ? "TRUE" : "FALSE"
        ], types: [:string, :string, :string, :integer, :integer, :string]
      end
    end

    send_data package.to_stream.read,
              filename: "late_kpi_#{kpi_month.strftime('%Y-%m')}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end
end

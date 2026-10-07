ActiveAdmin.register_page "KPI" do
  menu label: "KPI", priority: 6

  controller do
    helper_method :kpi_report, :kpi_month, :kpi_department_options, :kpi_show_all?, :kpi_employee_rows

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

    def kpi_employee_rows
      kpi_show_all? ? kpi_report.rows : kpi_report.flagged_rows
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
                     employee_rows: kpi_employee_rows, show_all: kpi_show_all? }
  end

  # Export the month being viewed as XLSX: department summary + per-employee sheet.
  # The employee sheet follows the same flagged-only / all filter as the screen.
  page_action :export, method: :get do
    require 'caxlsx'

    report   = kpi_report
    package  = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Department Summary") do |sheet|
      sheet.add_row ["Department", "Total Employees", "Total Lates", "KPI Deducted Employees"]
      report.department_summary.each do |summary|
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

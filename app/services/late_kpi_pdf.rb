# The admin KPI page as a PDF: the month's headline figures, the department
# summary and the employee list, in the order and with the filter the admin
# has on screen.
class LateKpiPdf < ReportPdf
  # summary_rows / employee_rows: already filtered and sorted by the caller.
  def initialize(report:, summary_rows:, employee_rows:, scope_label:, generated_by:, generated_at: Time.zone.now)
    @report = report
    @summary_rows = summary_rows
    @employee_rows = employee_rows
    @scope_label = scope_label
    @generated_by = generated_by
    @generated_at = generated_at
  end

  private

  def title
    "Late-arrival KPI report"
  end

  def subtitle
    "#{@report.month.strftime('%B %Y')}  |  #{@scope_label}  |  Generated #{generated_at.strftime('%d %b %Y, %I:%M %p')} by #{@generated_by}"
  end

  def body(pdf)
    rows = @report.rows
    figures(pdf, [["Employees", rows.size], ["Total lates", rows.sum(&:late_count)],
                  ["KPI deducted", rows.count(&:kpi_deducted)], ["Allowed lates per month", @report.limit]])

    section(pdf, "Department summary")
    if @summary_rows.empty?
      empty(pdf, "No employees in the departments you can view.")
    else
      data_table(pdf, ["Department", "Total employees", "Total lates", "KPI deducted employees"],
                 @summary_rows.map { |s| [safe(s.department), s.total_employees, s.total_lates, s.flagged_count] },
                 totals: ["Total", rows.size, rows.sum(&:late_count), rows.count(&:kpi_deducted)], widths: { 0 => 220 })
    end

    section(pdf, "Employees", "KPI is deducted for more than #{@report.limit} late arrivals in the month. Deducted employees are in red.")
    if @employee_rows.empty?
      empty(pdf, "No employees match this view.")
    else
      data_table(pdf, ["Employee", "Department", "Shift time", "Lates", "Allowed", "KPI deducted"],
                 @employee_rows.map { |row|
                   [safe(row.user.name), safe(row.department), row.user.shift_time&.strftime("%I:%M %p").to_s,
                    row.late_count, @report.limit, row.kpi_deducted ? "Yes" : "No"]
                 },
                 widths: { 0 => 180 }, numeric_from: 3, numeric_to: 4,
                 red_rows: @employee_rows.each_index.select { |i| @employee_rows[i].kpi_deducted })
    end
  end
end

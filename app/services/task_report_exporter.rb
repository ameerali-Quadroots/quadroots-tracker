require "csv"
require "caxlsx"

# Turns the department hours matrix into the three downloadable reports. Each
# builder returns [headers, rows] so the same data renders as CSV or xlsx.
class TaskReportExporter
  def initialize(department:, range:, tasks: nil)
    @department = department
    @range = range
    @tasks = tasks
  end

  def weekly_timing
    headers = ["Executive", "Date", "Task Hours", "Attendance Hours", "Untracked Hours"]

    rows = report.executives.flat_map do |executive|
      report.dates.filter_map do |date|
        cell = report.for(executive.id, date)
        next if cell[:task_seconds].zero? && cell[:attendance_seconds].zero?

        [executive.name, date.to_s, hours(cell[:task_seconds]),
         hours(cell[:attendance_seconds]), hours(cell[:gap_seconds])]
      end
    end

    [headers, rows]
  end

  def monthly_stats
    headers = ["Executive", "Task Hours", "Attendance Hours", "Untracked Hours",
               "Tasks Completed", "Over SLA", "Average Task Hours"]

    rows = report.executives.map do |executive|
      totals = report.totals_for(executive.id)
      completed = completed_counts[executive.id] || 0
      [executive.name,
       hours(totals[:task_seconds]),
       hours(totals[:attendance_seconds]),
       hours(totals[:gap_seconds]),
       completed,
       over_sla_counts[executive.id] || 0,
       completed.zero? ? 0.0 : hours(totals[:task_seconds] / completed)]
    end

    [headers, rows]
  end

  def task_list
    headers = ["Title", "Sprint", "Executive", "Type", "Status", "Priority",
               "Due Date", "Hours Logged", "Over SLA", "Parent"]

    scope = (@tasks || Task.none).includes(:assigned_to, :task_type, :parent, sprint: { project: :client })
    rows = scope.map do |task|
      [task.title,
       task.sprint&.name,
       task.assigned_to&.name,
       task.task_type&.name,
       task.status,
       task.priority,
       task.due_date&.to_s,
       hours(task.live_duration_seconds),
       task.over_sla? ? "Yes" : "No",
       task.parent&.title]
    end

    [headers, rows]
  end

  def to_csv(report_data)
    headers, rows = report_data
    CSV.generate do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end

  def to_xlsx(report_data)
    headers, rows = report_data
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Report") do |sheet|
      sheet.add_row headers
      rows.each { |row| sheet.add_row row }
    end
    package.to_stream.read
  end

  private

  def report
    @report ||= Reports::ExecutiveHours.new(department: @department, range: @range)
  end

  def hours(seconds) = (seconds.to_i / 3600.0).round(2)

  def completed_counts
    @completed_counts ||= Task.where(assigned_to_id: report.executives.map(&:id),
                                     status: "completed", ended_at: @range)
                              .group(:assigned_to_id).count
  end

  def over_sla_counts
    @over_sla_counts ||= Task.where(assigned_to_id: report.executives.map(&:id),
                                    status: "completed", over_sla: true, ended_at: @range)
                             .group(:assigned_to_id).count
  end
end

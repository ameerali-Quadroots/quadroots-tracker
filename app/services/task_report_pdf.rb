# The Task Manager report as a PDF: headline figures, tasks by executive, tasks
# by client, then the department's task list. Built from the same
# Reports::TaskDashboard the screen uses, so the two can never disagree.
class TaskReportPdf < ReportPdf
  TASK_LIMIT = 500
  STATUS_LABELS = TasksHelper::STATUS_ROLES.transform_values { |role| role[:label] }.freeze

  # tasks: the department's tasks (a relation). period_label: e.g. "Week of 05 Oct 2026".
  def initialize(report:, tasks:, department:, period_label:, generated_by:, generated_at: Time.zone.now)
    @report = report
    @tasks = tasks
    @department = department
    @period_label = period_label
    @generated_by = generated_by
    @generated_at = generated_at
  end

  private

  def page_layout
    :landscape
  end

  def title
    "Task Manager report"
  end

  def subtitle
    "#{@department&.name || 'Department'}  |  #{@period_label}  |  Generated #{generated_at.strftime('%d %b %Y, %I:%M %p')} by #{@generated_by&.name}"
  end

  def body(pdf)
    rate = @report.on_time_rate
    figures(pdf, [["Total tasks", @report.total_tasks], ["In flight", @report.in_flight], ["Completed", @report.completed_count],
                  ["Over budget", @report.over_sla_count], ["On-time rate", rate ? "#{rate}%" : "-"],
                  ["Hours logged", hours(@report.logged_seconds)]])
    section(pdf, "Tasks by executive", "Every task assigned to each person, and the time they logged in this period.")
    executives_table(pdf)
    section(pdf, "Tasks by client", "Tasks under each client's sprints. Internal work is everything not tied to a client.")
    clients_table(pdf)
    pdf.start_new_page
    section(pdf, "Task list", task_list_caption)
    tasks_table(pdf)
  end

  def executives_table(pdf)
    rows = @report.executive_breakdown
    return empty(pdf, "No executives in this department.") if rows.empty?

    body = rows.map do |row|
      [safe(row[:name]), row[:total], row[:pending], row[:in_progress], row[:paused], row[:completed], row[:over_sla],
       row[:on_time_rate] ? "#{row[:on_time_rate]}%" : "-", hours(row[:logged_seconds])]
    end
    totals = ["Total", *%i[total pending in_progress paused completed over_sla].map { |key| rows.sum { |row| row[key] } },
              "", hours(rows.sum { |row| row[:logged_seconds] })]
    data_table(pdf, ["Executive", "Total", "Not started", "Running", "Paused", "Done", "Over budget", "On time", "Hours logged"],
               body, totals: totals, widths: { 0 => 200 })
  end

  def clients_table(pdf)
    rows = @report.client_breakdown
    return empty(pdf, "No tasks yet.") if rows.empty?

    body = rows.map { |row| [safe(row[:name]), row[:total], row[:open], row[:completed], row[:over_sla], hours(row[:logged_seconds])] }
    totals = ["Total", *%i[total open completed over_sla].map { |key| rows.sum { |row| row[key] } }, hours(rows.sum { |row| row[:logged_seconds] })]
    data_table(pdf, ["Client", "Total tasks", "Open", "Done", "Over budget", "Hours logged"], body, totals: totals, widths: { 0 => 260 })
  end

  def tasks_table(pdf)
    return empty(pdf, "No tasks yet.") if listed_tasks.empty?

    logged = TaskWorkSession.where(task_id: listed_tasks.map(&:id)).group(:task_id).sum(:duration_seconds)
    body = listed_tasks.map do |task|
      [safe(task.title.to_s.truncate(70)), safe(task.sprint&.project&.client&.name || Reports::TaskDashboard::INTERNAL),
       safe(task.assigned_to&.name), STATUS_LABELS[task.status] || task.status.to_s.humanize, task.priority.to_s.capitalize,
       task.due_date ? task.due_date.strftime("%d %b %Y") : "-", hours(logged[task.id])]
    end
    data_table(pdf, ["Task", "Client", "Executive", "Status", "Priority", "Due", "Logged"], body, widths: { 0 => 270 }, numeric_from: 6)
  end

  # Newest work first within each status, open work before finished.
  def listed_tasks
    @listed_tasks ||= @tasks.includes(:assigned_to, sprint: { project: :client })
                            .order(Arel.sql("CASE tasks.status WHEN 'in_progress' THEN 0 WHEN 'paused' THEN 1 WHEN 'pending' THEN 2 ELSE 3 END"),
                                   created_at: :desc)
                            .limit(TASK_LIMIT).to_a
  end

  def task_list_caption
    total = @report.total_tasks
    total > TASK_LIMIT ? "The #{TASK_LIMIT} most relevant of #{total} tasks: open work first, newest first." : "All #{total} tasks: open work first, newest first."
  end
end

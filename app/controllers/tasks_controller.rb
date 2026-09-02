class TasksController < ApplicationController
  before_action :authenticate_user!
  # The whole module is off unless the user's department has it enabled, so this
  # guards every action — not just the manager-side ones.
  before_action :require_department_task_manager
  before_action -> { authorize_page!("task_manager") }, only: %i[dashboard new create import_preview import export update destroy]
  before_action :set_task, only: %i[start pause resume complete]

  def index
    redirect_to manager_task_manager? ? dashboard_tasks_path : my_tasks_tasks_path
  end

  def dashboard
    @period = params[:period] == "month" ? "month" : "week"
    @week_start = parse_week_start

    @tasks = department_tasks.top_level
                             .includes(:assigned_to, :task_type, { sprint: { project: :client } },
                                       subtasks: [:assigned_to, :task_type, { sprint: { project: :client } }])
                             .order(created_at: :desc)
    @tasks = @tasks.where(status: params[:status]) if params[:status].present?
    @tasks = @tasks.where(assigned_to_id: params[:executive_id]) if params[:executive_id].present?
    @tasks = @tasks.in_sprint(params[:sprint_id]) if params[:sprint_id].present?
    @tasks = @tasks.where(assigned_by_id: current_user.id) if params[:mine] == "1"

    @executives = department_executives
    @task_types = TaskType.where(department_id: current_user.department_id).order(:name)
    @clients = Client.where(department_id: current_user.department_id).includes(projects: :sprints).ordered
    @sprints = Sprint.for_department(current_user.department_id).includes(project: :client).ordered
    @selected_sprint = @sprints.detect { |s| s.id.to_s == params[:sprint_id].to_s }
    @stats = department_tasks.group(:status).count
    @over_sla_count = department_tasks.includes(:task_type).count(&:over_sla?)
    @tasks_per_executive = department_tasks.joins(:assigned_to).group("users.name").count

    @hours_report = Reports::ExecutiveHours.new(department: current_user.org_department, range: hours_range)
    @task = Task.new
  end

  REPORTS = %w[weekly_timing monthly_stats task_list].freeze

  def export
    report_name = params[:report].to_s
    return redirect_to(dashboard_tasks_path, alert: "Unknown report.") unless REPORTS.include?(report_name)

    @period = params[:period] == "month" ? "month" : "week"
    @week_start = parse_week_start

    exporter = TaskReportExporter.new(
      department: current_user.org_department,
      range: hours_range,
      tasks: department_tasks
    )
    data = exporter.public_send(report_name)
    stamp = Date.current.strftime("%Y%m%d")

    if params[:format].to_s == "xlsx"
      send_data exporter.to_xlsx(data), filename: "#{report_name}_#{stamp}.xlsx",
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    else
      send_data exporter.to_csv(data), filename: "#{report_name}_#{stamp}.csv", type: "text/csv"
    end
  end

  # The task detail popup. Readable by a manager anywhere in their department
  # and by the executive the task belongs to; rendered as a bare partial
  # because it is fetched into a modal, not visited as a page.
  def show
    task = department_tasks.includes(:assigned_to, :assigned_by, :task_type, :parent,
                                     { sprint: { project: :client } },
                                     { subtasks: %i[assigned_to task_type] },
                                     :work_sessions)
                           .find_by(id: params[:id])
    return forbid! if task.nil?
    return forbid! unless can_view?("task_manager") || task.assigned_to_id == current_user.id

    render partial: "tasks/task_detail", locals: { task: task }, layout: false
  end

  def update
    task = department_tasks.find_by(id: params[:id])
    return forbid! if task.nil?

    if task.update(task_params.except(:new_task_type_name))
      redirect_back fallback_location: dashboard_tasks_path, notice: "Task updated."
    else
      redirect_back fallback_location: dashboard_tasks_path,
                    alert: task.errors.full_messages.to_sentence
    end
  end

  def destroy
    task = department_tasks.find_by(id: params[:id])
    return forbid! if task.nil?

    title = task.title
    count = task.subtasks.count
    task.destroy
    suffix = count.positive? ? " and #{count} subtask(s)" : ""
    redirect_to dashboard_tasks_path, notice: "Deleted #{title}#{suffix}."
  end

  def import_preview
    importer, error = build_importer
    return redirect_to(dashboard_tasks_path(tab: "tasks"), alert: error) if importer.nil?

    render partial: "tasks/import_preview", locals: { importer: importer }
  end

  def import
    importer, error = build_importer
    return redirect_to(dashboard_tasks_path(tab: "tasks"), alert: error) if importer.nil?

    if importer.valid?
      created = importer.commit!
      redirect_to dashboard_tasks_path(tab: "tasks"), notice: "Imported #{created} task(s)."
    else
      redirect_to dashboard_tasks_path(tab: "tasks"),
                  alert: "Nothing was imported — #{importer.error_count} row(s) have errors."
    end
  end

  def my_tasks
    mine = Task.for_executive(current_user)
    # A subtask is nested under its parent only when the parent is also mine;
    # otherwise it would silently vanish from the executive's list.
    nested_ids = mine.subtasks_only.where(parent_id: mine.select(:id)).pluck(:id)

    @tasks = mine.where.not(id: nested_ids)
                 .includes(:task_type, subtasks: :task_type)
                 .order(created_at: :desc)
  end

  def new
    @task = Task.new
    @executives = current_user.direct_reports.joins(:access_role).where(roles: { name: "Executive" }).order(:name)
    @task_types = TaskType.where(department_id: current_user.department_id).order(:name)
  end

  def create
    attrs = task_params.to_h
    new_type_name = attrs.delete("new_task_type_name").to_s.strip

    if attrs["task_type_id"] == "__new__" || (attrs["task_type_id"].blank? && new_type_name.present?)
      if new_type_name.blank?
        redirect_to dashboard_tasks_path, alert: "Please enter a name for the new task type." and return
      end

      # Reused if a type with this name already exists in the department
      # (matches the tasks_type unique index on department_id + name).
      task_type = TaskType.find_or_initialize_by(department: current_user.org_department, name: new_type_name)
      task_type.sla_minutes = attrs["custom_sla_minutes"].presence || 0 if task_type.new_record?
      task_type.save!
      attrs["task_type_id"] = task_type.id
    end

    @task = Task.new(attrs.merge(assigned_by: current_user))

    if @task.save
      notify_executive_of_new_task(@task)
      redirect_to dashboard_tasks_path, notice: "Task assigned."
    else
      redirect_to dashboard_tasks_path, alert: @task.errors.full_messages.to_sentence
    end
  end

  def start
    return forbid! unless owns?(@task)

    if Task.for_executive(current_user).in_progress.exists?
      redirect_to my_tasks_tasks_path, alert: "Finish or pause your current task before starting another."
    elsif @task.start!
      redirect_to my_tasks_tasks_path, notice: "Task started."
    else
      redirect_to my_tasks_tasks_path, alert: "This task cannot be started."
    end
  end

  def pause
    return forbid! unless owns?(@task)

    if @task.pause!(reason: params[:reason])
      redirect_to my_tasks_tasks_path, notice: "Task paused."
    else
      redirect_to my_tasks_tasks_path, alert: "This task cannot be paused."
    end
  end

  def resume
    return forbid! unless owns?(@task)

    if Task.for_executive(current_user).in_progress.exists?
      redirect_to my_tasks_tasks_path, alert: "Finish or pause your current task before resuming another."
    elsif @task.resume!
      redirect_to my_tasks_tasks_path, notice: "Task resumed."
    else
      redirect_to my_tasks_tasks_path, alert: "This task cannot be resumed."
    end
  end

  def complete
    return forbid! unless owns?(@task)

    if @task.complete!
      redirect_to my_tasks_tasks_path, notice: "Task completed."
    else
      redirect_to my_tasks_tasks_path, alert: "This task cannot be completed."
    end
  end

  private

  # Returns [importer, nil] or [nil, error_message]. A sprint id from another
  # department must never reach the importer, and the manager needs to be told
  # which of the two things went wrong.
  def build_importer
    return [nil, "Choose a CSV file to import."] if params[:file].blank?

    sprint = nil
    if params[:sprint_id].present?
      sprint = Sprint.for_department(current_user.department_id).find_by(id: params[:sprint_id])
      return [nil, "That sprint doesn't belong to your department."] if sprint.nil?
    end

    importer = TaskCsvImporter.new(
      csv_text: params[:file].read,
      manager: current_user,
      sprint: sprint,
      create_missing_types: params[:create_missing_types] == "1"
    )
    [importer, nil]
  end

  # Department is the visibility boundary, not "tasks I assigned" — a manager
  # needs to see what every executive in the department is carrying.
  def department_tasks
    Task.joins(:assigned_to).where(users: { department_id: current_user.department_id })
  end

  def department_executives
    User.employed.joins(:access_role)
        .where(department_id: current_user.department_id, roles: { name: "Executive" })
        .order(:name)
  end

  def parse_week_start
    (Date.parse(params[:week_start]) rescue Date.current).beginning_of_week
  end

  def hours_range
    if @period == "month"
      @week_start.beginning_of_month.beginning_of_day..@week_start.end_of_month.end_of_day
    else
      @week_start.beginning_of_day..(@week_start + 6.days).end_of_day
    end
  end

  # Task Manager is a role capability (Manager) gated additionally by whether
  # the manager's own department has it turned on (Settings -> Departments in
  # the admin panel) — some departments don't use it at all.
  def manager_task_manager?
    can_view?("task_manager") && current_user.org_department&.task_manager_enabled?
  end

  def require_department_task_manager
    return if current_user.org_department&.task_manager_enabled?

    redirect_to root_path, alert: "Task Manager isn't enabled for your department."
  end

  def set_task
    @task = Task.find(params[:id])
  end

  # SLA is a manager-side tracking figure, deliberately left out of what the
  # executive sees — here and on their My Tasks page.
  def notify_executive_of_new_task(task)
    message = ":clipboard: New task assigned: *#{task.title}*\n" \
              "Type: #{task.task_type.name}\n" \
              "Priority: #{task.priority.capitalize}" \
              "#{task.due_date.present? ? " · Due #{task.due_date.strftime('%d %b %Y')}" : ''}\n" \
              "Assigned by: #{task.assigned_by.name}"

    SlackNotifier.notify(message, email: task.assigned_to.email)
  end

  def owns?(task)
    task.assigned_to_id == current_user.id
  end

  def forbid!
    redirect_to root_path, alert: "You are not authorized to do that."
  end

  def task_params
    params.require(:task).permit(:title, :description, :priority, :due_date, :assigned_to_id,
                                 :task_type_id, :custom_sla_minutes, :new_task_type_name,
                                 :parent_id, :sprint_id)
  end
end

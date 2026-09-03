# The Task Manager module. Two faces on the same data:
#
#   * #dashboard — the manager's view of their whole department.
#   * #my_tasks  — the executive's view of the work assigned to them.
#
# Every mutation answers twice over: a redirect for a plain form post, and a
# JSON envelope of re-rendered regions for a fetch() from the page. The regions
# mechanism is deliberate — the server re-renders the parts of the page its own
# change touched and the browser swaps them in by selector, so the screen can
# never drift out of step with the database the way hand-patched rows do.
class TasksController < ApplicationController
  include DepartmentTaskScope

  before_action -> { authorize_page!("task_manager") },
                only: %i[dashboard new create import_preview import export update destroy move]
  before_action :set_period, only: %i[dashboard export]
  before_action :set_task, only: %i[start pause resume complete]

  REPORTS = %w[weekly_timing monthly_stats task_list].freeze

  def index
    redirect_to manager_task_manager? ? dashboard_tasks_path : my_tasks_tasks_path
  end

  def dashboard
    load_dashboard

    return render_regions(dashboard_regions(params[:regions])) if ajax?

    render :dashboard
  end

  def my_tasks
    load_my_tasks

    return render_regions(my_tasks_regions(params[:regions])) if ajax?

    render :my_tasks
  end

  # The task drawer. Readable by a manager anywhere in their department and by
  # the executive the task belongs to; rendered as a bare partial because it is
  # fetched into the drawer, not visited as a page.
  def show
    task = find_visible_task(params[:id])
    return forbid! if task.nil?

    task = Task.includes(:assigned_to, :assigned_by, :task_type, :parent,
                         { sprint: { project: :client } },
                         { subtasks: %i[assigned_to task_type] },
                         :work_sessions, { comments: :user })
               .find(task.id)

    render partial: "tasks/drawer",
           locals: { task: task, manager: can_view?("task_manager") }, layout: false
  end

  def new
    @task = Task.new
    @executives = department_executives
    @task_types = department_task_types
  end

  def create
    attrs = task_params.to_h
    type_id, error = resolve_task_type(attrs)
    return respond_error(error) if error.present?

    attrs["task_type_id"] = type_id
    @task = Task.new(attrs.merge(assigned_by: current_user))

    if @task.save
      notify_executive_of_new_task(@task)
      respond_ok("Assigned “#{@task.title}” to #{@task.assigned_to.name}.")
    else
      respond_error(@task.errors.full_messages.to_sentence)
    end
  end

  def update
    task = department_tasks.find_by(id: params[:id])
    return forbid! if task.nil?

    if task.update(task_params.except(:new_task_type_name))
      respond_ok("Saved “#{task.title}”.")
    else
      respond_error(task.errors.full_messages.to_sentence)
    end
  end

  def destroy
    task = department_tasks.find_by(id: params[:id])
    return forbid! if task.nil?

    title = task.title
    count = task.subtasks.count
    task.destroy
    suffix = count.positive? ? " and #{count} subtask#{'s' if count > 1}" : ""
    respond_ok("Deleted “#{title}”#{suffix}.")
  end

  def export
    report_name = params[:report].to_s
    return redirect_to(dashboard_tasks_path, alert: "Unknown report.") unless REPORTS.include?(report_name)

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

  def import_preview
    importer, error = build_importer
    return respond_error(error, fallback: tasks_tab_path) if importer.nil?

    render json: {
      ok: importer.valid?,
      html: render_to_string(partial: "tasks/import_preview",
                             locals: { importer: importer }, formats: [:html])
    }
  end

  def import
    importer, error = build_importer
    return respond_error(error, fallback: tasks_tab_path) if importer.nil?

    unless importer.valid?
      return respond_error("Nothing was imported — #{importer.error_count} row#{'s' if importer.error_count > 1} need fixing.",
                           fallback: tasks_tab_path)
    end

    created = importer.commit!
    respond_ok("Imported #{created} task#{'s' if created != 1}.", fallback: tasks_tab_path)
  end

  # --- The executive's timer ------------------------------------------------
  #
  # Only one task may run at a time, so start and resume both have to check for
  # an existing runner before they change anything.

  def start
    return forbid! unless owns?(@task)
    return respond_error(BUSY_MESSAGE, view: :my_tasks) if another_task_running?

    guarded_transition(:start!, "Started “#{@task.title}”.", "This task cannot be started.")
  end

  def resume
    return forbid! unless owns?(@task)
    return respond_error(BUSY_MESSAGE, view: :my_tasks) if another_task_running?

    guarded_transition(:resume!, "Resumed “#{@task.title}”.", "This task cannot be resumed.")
  end

  def pause
    return forbid! unless owns?(@task)

    if @task.pause!(reason: params[:reason])
      respond_ok("Paused “#{@task.title}”.", view: :my_tasks)
    else
      respond_error("This task cannot be paused.", view: :my_tasks)
    end
  end

  def complete
    return forbid! unless owns?(@task)

    guarded_transition(:complete!, "Completed “#{@task.title}”.", "This task cannot be completed.")
  end

  # Dragging a card between board columns. The board is a view onto the same
  # timer state machine the executive drives, so a move is translated into the
  # real lifecycle call rather than writing the status column directly — a
  # dragged card starts and stops the clock exactly as the buttons do.
  def move
    task = department_tasks.find_by(id: params[:id])
    return forbid! if task.nil?

    target = params[:status].to_s
    view = params[:sprint_id].present? ? :sprint : :dashboard
    return respond_error("#{target.humanize} isn't a column.", view: view) unless Task.statuses.key?(target)
    return respond_ok("“#{task.title}” is already there.", view: view) if task.status == target

    message = apply_move(task, target)
    return respond_error(message[:error], view: view) if message[:error]

    respond_ok(message[:notice], view: view)
  end

  private

  # Returns {notice:} or {error:}. Each branch names the reason a move is
  # refused, because "that didn't work" on a drag tells the manager nothing.
  def apply_move(task, target)
    case target
    when "in_progress"
      if (running = Task.for_executive(task.assigned_to).in_progress.where.not(id: task.id).first)
        return { error: "#{task.assigned_to.name} is already working on “#{running.title}”. "                         "Move that one out of Running first." }
      end

      started = task.pending? ? task.start! : task.resume!
      started ? { notice: "Started “#{task.title}”." } : { error: "“#{task.title}” cannot be started." }
    when "paused"
      # A task that was never started has no clock to pause.
      return { error: "“#{task.title}” hasn't been started yet, so there is nothing to pause." } if task.pending?

      task.pause!(reason: "Moved to Paused on the board") ? { notice: "Paused “#{task.title}”." }
                                                          : { error: "“#{task.title}” cannot be paused." }
    when "completed"
      return { error: "“#{task.title}” hasn't been started yet. Start it before marking it done." } if task.pending?

      task.complete! ? { notice: "Completed “#{task.title}”." } : { error: "“#{task.title}” cannot be completed." }
    when "pending"
      # Deliberately one-way: rewinding to Not started would have to throw away
      # or silently keep logged hours, and either answer misreports the sprint.
      { error: "“#{task.title}” has already been started, so it can't go back to Not started." }
    end
  end

  BUSY_MESSAGE = "Finish or pause your current task before starting another.".freeze

  def another_task_running?
    Task.for_executive(current_user).in_progress.where.not(id: @task.id).exists?
  end

  def guarded_transition(action, success, failure)
    if @task.public_send(action)
      respond_ok(success, view: :my_tasks)
    else
      respond_error(failure, view: :my_tasks)
    end
  end

  # --- Loading --------------------------------------------------------------

  def load_dashboard
    @executives = department_executives
    @task_types = department_task_types
    @sprints = department_sprints.includes(project: :client).ordered
    @clients = department_clients
    @selected_sprint = @sprints.detect { |s| s.id.to_s == params[:sprint_id].to_s }
    @tasks = filtered_tasks
    @report = Reports::TaskDashboard.new(scope: department_tasks, executives: @executives,
                                         range: hours_range, previous_range: previous_hours_range)
    @hours_report = Reports::ExecutiveHours.new(department: current_user.org_department, range: hours_range)
    @task = Task.new
  end

  def load_my_tasks
    mine = Task.for_executive(current_user)
    # A subtask is nested under its parent only when the parent is also mine;
    # otherwise it would silently vanish from the executive's list.
    nested_ids = mine.subtasks_only.where(parent_id: mine.select(:id)).pluck(:id)

    @tasks = mine.where.not(id: nested_ids)
                 .includes(:task_type, :assigned_by, { sprint: { project: :client } },
                           subtasks: %i[task_type assigned_by])
                 .order(created_at: :desc)
    @scope = params[:scope].presence_in(%w[open completed all]) || "open"
    @visible_tasks = case @scope
                     when "completed" then @tasks.select(&:completed?)
                     when "all" then @tasks.to_a
                     else @tasks.reject(&:completed?)
                     end
    @report = Reports::ExecutiveDashboard.new(user: current_user, tasks: @tasks)
  end

  def filtered_tasks
    scope = department_tasks.top_level
                            .includes(:assigned_to, :task_type, { sprint: { project: :client } },
                                      subtasks: [:assigned_to, :task_type, { sprint: { project: :client } }])
                            .order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(assigned_to_id: params[:executive_id]) if params[:executive_id].present?
    scope = scope.in_sprint(params[:sprint_id]) if params[:sprint_id].present?
    scope = scope.where(assigned_by_id: current_user.id) if params[:mine] == "1"
    scope = scope.where(priority: "urgent") if params[:priority] == "urgent"

    if params[:q].present?
      term = "%#{params[:q].to_s.strip.downcase}%"
      scope = scope.where("LOWER(tasks.title) LIKE :t OR LOWER(tasks.description) LIKE :t", t: term)
    end

    scope = scope.where(id: over_sla_task_ids) if params[:over] == "1"
    scope
  end

  # An unfinished task's SLA breach depends on the clock right now, so this
  # cannot be a pure WHERE. Finished work is read straight off the column;
  # only the started-but-unfinished handful is measured in Ruby.
  def over_sla_task_ids
    finished = department_tasks.where(status: "completed", over_sla: true).pluck(:id)
    running = department_tasks.where(status: %w[in_progress paused])
                              .where.not(started_at: nil)
                              .includes(:task_type)
                              .select(&:over_sla?).map(&:id)
    finished + running
  end

  # --- AJAX plumbing --------------------------------------------------------

  def ajax?
    request.xhr? || request.format.json?
  end

  # Regions are addressed by the CSS selector they live at, so the browser side
  # is one loop over the payload rather than a switch per action.
  DASHBOARD_REGIONS = {
    "summary" => "tasks/manager_summary",
    "charts" => "tasks/manager_charts",
    "tasks" => "tasks/panel_tasks",
    "team_hours" => "tasks/panel_team_hours",
    "sprints" => "tasks/panel_sprints"
  }.freeze

  MY_TASKS_REGIONS = {
    "focus" => "tasks/executive_focus",
    "summary" => "tasks/executive_summary",
    "tasks" => "tasks/panel_my_tasks"
  }.freeze

  SPRINT_REGIONS = {
    "summary" => "sprints/summary",
    "board" => "sprints/board",
    "people" => "sprints/people"
  }.freeze

  # What a mutation sends back by default. Deliberately narrower than the full
  # map: re-rendering every region meant a single "start task" click rebuilt
  # the team-hours matrix and the sprint list too — work nobody asked for, on
  # panels that are not even on screen. The heavy tabs refresh when the person
  # actually opens them.
  MUTATION_REGIONS = %w[summary charts tasks].freeze
  MY_TASKS_MUTATION_REGIONS = %w[focus summary tasks].freeze

  def dashboard_regions(requested = nil)
    build_regions(DASHBOARD_REGIONS, requested)
  end

  def my_tasks_regions(requested = nil)
    build_regions(MY_TASKS_REGIONS, requested)
  end

  def build_regions(map, requested)
    names = requested.presence&.to_s&.split(",")&.map(&:strip) || map.keys
    map.slice(*names).transform_values do |partial|
      render_to_string(partial: partial, formats: [:html])
    end.transform_keys { |name| "#tm-region-#{name.tr('_', '-')}" }
  end

  def render_regions(regions, message: nil, ok: true)
    render json: { ok: ok, message: message, regions: regions }
  end

  # A mutation reloads whichever view the request came from, so the page it
  # updates is the page the person is looking at.
  def respond_ok(message, view: :dashboard, fallback: nil)
    return redirect_back(fallback_location: fallback || fallback_for(view), notice: message) unless ajax?

    regions = regions_for(view)
    render json: { ok: true, message: message, regions: regions }
  end

  def respond_error(message, view: :dashboard, status: :unprocessable_entity, fallback: nil)
    return redirect_back(fallback_location: fallback || fallback_for(view), alert: message) unless ajax?

    render json: { ok: false, error: message }, status: status
  end

  # A mutation answers with the regions its own change touches. The caller can
  # ask for a different set with ?regions=, which is how the tabs fetch the
  # panels they own.
  def regions_for(view)
    case view
    when :my_tasks
      load_my_tasks
      my_tasks_regions(params[:regions].presence || MY_TASKS_MUTATION_REGIONS.join(","))
    when :sprint
      sprint = department_sprints.includes(project: :client).find_by(id: params[:sprint_id])
      return {} if sprint.nil?

      load_sprint_board(sprint)
      build_regions(SPRINT_REGIONS, nil)
    else
      load_dashboard
      dashboard_regions(params[:regions].presence || MUTATION_REGIONS.join(","))
    end
  end

  def fallback_for(view)
    case view
    when :my_tasks then my_tasks_tasks_path
    when :sprint then params[:sprint_id].present? ? sprint_path(params[:sprint_id]) : dashboard_tasks_path
    else dashboard_tasks_path
    end
  end

  def tasks_tab_path
    dashboard_tasks_path(tab: "tasks")
  end

  # --- Creation helpers -----------------------------------------------------

  # Returns [task_type_id, nil] or [nil, error]. A manager can invent a task
  # type inline instead of leaving the form to go and configure one first.
  def resolve_task_type(attrs)
    new_type_name = attrs.delete("new_task_type_name").to_s.strip
    inline = attrs["task_type_id"] == "__new__" ||
             (attrs["task_type_id"].blank? && new_type_name.present?)
    return [attrs["task_type_id"], nil] unless inline
    return [nil, "Enter a name for the new task type."] if new_type_name.blank?

    # Reused if a type with this name already exists in the department (matches
    # the task_types unique index on department_id + name).
    task_type = TaskType.find_or_initialize_by(department: current_user.org_department, name: new_type_name)
    task_type.sla_minutes = attrs["custom_sla_minutes"].presence || 0 if task_type.new_record?
    task_type.save!
    [task_type.id, nil]
  end

  # Returns [importer, nil] or [nil, error_message]. A sprint id from another
  # department must never reach the importer, and the manager needs to be told
  # which of the two things went wrong.
  def build_importer
    return [nil, "Choose a CSV file to import."] if params[:file].blank?

    sprint = nil
    if params[:sprint_id].present?
      sprint = department_sprints.find_by(id: params[:sprint_id])
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

  # --- Misc -----------------------------------------------------------------

  def set_period
    @period = params[:period] == "month" ? "month" : "week"
    @week_start = parse_week_start
  end

  def parse_week_start
    (Date.parse(params[:week_start]) rescue Date.current).beginning_of_week
  end

  def hours_range
    set_period if @period.blank?

    if @period == "month"
      @week_start.beginning_of_month.beginning_of_day..@week_start.end_of_month.end_of_day
    else
      @week_start.beginning_of_day..(@week_start + 6.days).end_of_day
    end
  end

  def previous_hours_range
    if @period == "month"
      previous = @week_start.beginning_of_month - 1.month
      previous.beginning_of_month.beginning_of_day..previous.end_of_month.end_of_day
    else
      start = @week_start - 7.days
      start.beginning_of_day..(start + 6.days).end_of_day
    end
  end

  def set_task
    @task = Task.find_by(id: params[:id])
    forbid! if @task.nil?
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

  def task_params
    params.require(:task).permit(:title, :description, :priority, :due_date, :assigned_to_id,
                                 :task_type_id, :custom_sla_minutes, :new_task_type_name,
                                 :parent_id, :sprint_id)
  end
end

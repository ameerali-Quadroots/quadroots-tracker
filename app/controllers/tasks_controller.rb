class TasksController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("task_manager") }, only: %i[dashboard new create]
  before_action :require_department_task_manager, only: %i[dashboard new create]
  before_action :set_task, only: %i[start pause resume complete]

  def index
    redirect_to manager_task_manager? ? dashboard_tasks_path : my_tasks_tasks_path
  end

  def dashboard
    @tasks = Task.for_manager(current_user).includes(:assigned_to, :task_type).order(created_at: :desc)
    @tasks = @tasks.where(status: params[:status]) if params[:status].present?
    @tasks = @tasks.where(assigned_to_id: params[:executive_id]) if params[:executive_id].present?

    @executives = current_user.direct_reports.joins(:access_role).where(roles: { name: "Executive" }).order(:name)
    @task_types = TaskType.where(department_id: current_user.department_id).order(:name)
    @stats = Task.for_manager(current_user).group(:status).count
    @over_sla_count = Task.for_manager(current_user).includes(:task_type).count(&:over_sla?)
    @tasks_per_executive = Task.for_manager(current_user).joins(:assigned_to).group("users.name").count
    @task = Task.new
  end

  def my_tasks
    @tasks = Task.for_executive(current_user).includes(:task_type).order(created_at: :desc)
  end

  def new
    @task = Task.new
    @executives = current_user.direct_reports.joins(:access_role).where(roles: { name: "Executive" }).order(:name)
    @task_types = TaskType.where(department_id: current_user.department_id).order(:name)
  end

  def create
    @task = Task.new(task_params.merge(assigned_by: current_user))

    if @task.save
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

  def owns?(task)
    task.assigned_to_id == current_user.id
  end

  def forbid!
    redirect_to root_path, alert: "You are not authorized to do that."
  end

  def task_params
    params.require(:task).permit(:title, :description, :priority, :due_date, :assigned_to_id, :task_type_id)
  end
end

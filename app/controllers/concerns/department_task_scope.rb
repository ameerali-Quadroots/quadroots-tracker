# Everything the Task Manager module needs to answer "may this person see this,
# and which records are theirs to see". Previously duplicated verbatim across
# TasksController and SprintsController.
#
# Two separate gates, deliberately:
#   * the module is off entirely unless the user's department has it enabled;
#   * the manager-side pages additionally need the task_manager permission.
# Department — not "tasks I assigned" — is the visibility boundary, because a
# manager has to see what every executive in the department is carrying.
module DepartmentTaskScope
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    before_action :require_department_task_manager
    helper_method :manager_task_manager?
  end

  private

  def require_department_task_manager
    return if current_user.org_department&.task_manager_enabled?

    redirect_to root_path, alert: "Task Manager isn't enabled for your department."
  end

  def manager_task_manager?
    can_view?("task_manager") && current_user.org_department&.task_manager_enabled?
  end

  def department_tasks
    Task.joins(:assigned_to).where(users: { department_id: current_user.department_id })
  end

  def department_executives
    User.employed.joins(:access_role)
        .where(department_id: current_user.department_id, roles: { name: "Executive" })
        .order(:name)
  end

  def department_task_types
    TaskType.where(department_id: current_user.department_id).order(:name)
  end

  def department_sprints
    Sprint.for_department(current_user.department_id)
  end

  def department_clients
    Client.where(department_id: current_user.department_id).includes(projects: :sprints).ordered
  end

  # The one place that decides whether this user may open a given task at all:
  # their own task, or any task in their department if they are a manager.
  def find_visible_task(id)
    task = Task.includes(:assigned_to).find_by(id: id)
    return nil if task.nil?

    task.visible_to?(current_user, manager: can_view?("task_manager")) ? task : nil
  end

  # A background request must never be answered with a redirect: fetch() follows
  # it transparently, so the caller would receive 200 OK carrying the sign-in or
  # dashboard page and inject it wherever the real answer belonged. Browsers
  # navigating normally still get the redirect and the flash.
  # Everything the sprint board renders. Shared because a card dragged between
  # columns is handled by TasksController but has to answer with the board
  # SprintsController drew, and the two must agree on what a board is.
  def load_sprint_board(sprint)
    @sprint = sprint
    @tasks = sprint.tasks.top_level
                   .includes(:assigned_to, :task_type, subtasks: %i[assigned_to task_type])
                   .order(:position, created_at: :asc)
    @by_status = Task.statuses.keys.index_with { |status| @tasks.select { |t| t.status == status } }

    # Hours in this sprint, by whoever actually did the work — subtasks
    # included, since a subtask can belong to a different executive.
    task_ids = sprint.tasks.pluck(:id)
    @hours_by_user = TaskWorkSession.where(task_id: task_ids).group(:user_id).sum(:duration_seconds)
    @people = User.where(id: @hours_by_user.keys).index_by(&:id)
  end

  def forbid!(message = "You are not authorized to do that.")
    if request.xhr? || request.format.json?
      render json: { ok: false, error: message }, status: :forbidden
    else
      redirect_to root_path, alert: message
    end
  end
end

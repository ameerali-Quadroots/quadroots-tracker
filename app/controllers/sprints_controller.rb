# Client / project / sprint management for a department's Task Manager. Every
# action redirects back to the Sprints tab of the task dashboard — this module
# has no pages of its own.
class SprintsController < ApplicationController
  include DepartmentTaskScope

  before_action -> { authorize_page!("task_manager") }

  # Every sprint in the department, grouped by client — the page the
  # breadcrumb's "Sprints" step points at.
  def index
    @sprints = department_sprints.includes(project: :client).ordered
    @clients = department_clients
    @executives = department_executives
    @task_types = department_task_types

    ids = @sprints.map(&:id)
    @task_counts = Task.where(sprint_id: ids).group(:sprint_id, :status).count
    @logged = TaskWorkSession.joins(:task).where(tasks: { sprint_id: ids })
                             .group("tasks.sprint_id").sum(:duration_seconds)
  end

  def show
    @sprint = department_sprints.includes(project: :client).find_by(id: params[:id])
    return redirect_to(root_path, alert: "You are not authorized to do that.") if @sprint.nil?

    load_sprint_board(@sprint)
    @sprints = department_sprints.includes(project: :client).ordered
    @executives = department_executives
    @task_types = department_task_types
    @clients = department_clients
  end

  def create
    project = department_projects.find_by(id: params.dig(:sprint, :project_id))
    return back_with(alert: "Unknown project.") if project.nil?

    sprint = project.sprints.new(sprint_params)
    if sprint.save
      back_with(notice: "Sprint created.")
    else
      back_with(alert: sprint.errors.full_messages.to_sentence)
    end
  end

  def update
    sprint = department_sprints.find_by(id: params[:id])
    return back_with(alert: "Unknown sprint.") if sprint.nil?

    if sprint.update(sprint_params)
      back_with(notice: "Sprint updated.")
    else
      back_with(alert: sprint.errors.full_messages.to_sentence)
    end
  end

  # Unfinished work does not disappear at the end of a cycle — it moves to the
  # next one, the way a Jira sprint closes.
  def carry_over
    sprint = department_sprints.find_by(id: params[:id])
    target = department_sprints.find_by(id: params[:target_sprint_id])
    return back_with(alert: "Unknown sprint.") if sprint.nil? || target.nil?

    moved = sprint.tasks.where.not(status: "completed").update_all(sprint_id: target.id)
    back_with(notice: "Moved #{moved} task(s) to #{target.name}.")
  end

  private

  def department_projects
    Project.joins(:client).where(clients: { department_id: current_user.department_id })
  end

  def sprint_params
    params.require(:sprint).permit(:name, :goal, :start_date, :end_date, :status)
  end

  def back_with(**flash_opts)
    redirect_to dashboard_tasks_path(tab: "sprints"), **flash_opts
  end
end

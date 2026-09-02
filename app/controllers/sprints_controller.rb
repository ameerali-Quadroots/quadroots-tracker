# Client / project / sprint management for a department's Task Manager. Every
# action redirects back to the Sprints tab of the task dashboard — this module
# has no pages of its own.
class SprintsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_department_task_manager
  before_action -> { authorize_page!("task_manager") }

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

  def department_sprints
    Sprint.for_department(current_user.department_id)
  end

  def sprint_params
    params.require(:sprint).permit(:name, :goal, :start_date, :end_date, :status)
  end

  def back_with(**flash_opts)
    redirect_to dashboard_tasks_path(tab: "sprints"), **flash_opts
  end

  def require_department_task_manager
    return if current_user.org_department&.task_manager_enabled?

    redirect_to root_path, alert: "Task Manager isn't enabled for your department."
  end
end

class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("task_manager") }

  def create
    client = Client.where(department_id: current_user.department_id)
                   .find_by(id: params.dig(:project, :client_id))
    return redirect_to(dashboard_tasks_path(tab: "sprints"), alert: "Unknown client.") if client.nil?

    project = client.projects.new(project_params)
    if project.save
      redirect_to dashboard_tasks_path(tab: "sprints"), notice: "Project created."
    else
      redirect_to dashboard_tasks_path(tab: "sprints"), alert: project.errors.full_messages.to_sentence
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :status, :start_date, :target_end_date)
  end
end

# A project is one body of work for a client, delivered as a series of sprints.
# Its page is the middle step of a sprint's breadcrumb.
class ProjectsController < ApplicationController
  include DepartmentTaskScope

  before_action -> { authorize_page!("task_manager") }

  def show
    @project = Project.joins(:client)
                      .where(clients: { department_id: current_user.department_id })
                      .includes(:client, :sprints)
                      .find_by(id: params[:id])
    return redirect_to(clients_path, alert: "That project isn't in your department.") if @project.nil?

    @client = @project.client
    @sprints = @project.sprints.order(start_date: :desc)

    ids = @sprints.map(&:id)
    @task_counts = Task.where(sprint_id: ids).group(:sprint_id, :status).count
    @logged = TaskWorkSession.joins(:task).where(tasks: { sprint_id: ids })
                             .group("tasks.sprint_id").sum(:duration_seconds)
    @logged_total = @logged.values.sum
    @executives = department_executives
    @task_types = department_task_types
    @clients = department_clients
  end

  def create
    client = department_clients.find_by(id: params.dig(:project, :client_id))
    return redirect_back(fallback_location: clients_path, alert: "Unknown client.") if client.nil?

    project = client.projects.new(project_params)
    if project.save
      redirect_to project_path(project), notice: "Added #{project.name} for #{client.name}."
    else
      redirect_back fallback_location: client_path(client),
                    alert: project.errors.full_messages.to_sentence
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :status, :start_date, :target_end_date)
  end
end

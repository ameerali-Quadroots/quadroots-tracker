# Clients belong to a department's Task Manager. The index and show pages make
# the sprint breadcrumb navigable: a client name is a page, not a dead label.
class ClientsController < ApplicationController
  include DepartmentTaskScope

  before_action -> { authorize_page!("task_manager") }

  def index
    @clients = department_clients.includes(projects: :sprints)

    client_ids = @clients.map(&:id)
    @sprint_counts = Sprint.joins(project: :client).where(clients: { id: client_ids })
                           .group("clients.id").count
    @logged = TaskWorkSession.joins(task: { sprint: { project: :client } })
                             .where(clients: { id: client_ids })
                             .group("clients.id").sum(:duration_seconds)
    @open_tasks = Task.joins(sprint: { project: :client })
                      .where(clients: { id: client_ids })
                      .where.not(status: "completed")
                      .group("clients.id").count
  end

  def show
    @client = department_clients.find_by(id: params[:id])
    return redirect_to(clients_path, alert: "That client isn't in your department.") if @client.nil?

    @projects = @client.projects.includes(:sprints).order(:name)
    # The New project / New sprint modals this page renders need the pickers.
    @clients = department_clients

    sprint_ids = Sprint.where(project_id: @projects.map(&:id)).pluck(:id)
    @logged_by_project = TaskWorkSession.joins(task: :sprint)
                                        .where(tasks: { sprint_id: sprint_ids })
                                        .group("sprints.project_id").sum(:duration_seconds)
    @counts_by_project = Task.joins(:sprint).where(sprint_id: sprint_ids)
                             .group("sprints.project_id", :status).count
    @logged_total = @logged_by_project.values.sum
  end

  def create
    client = Client.new(client_params.merge(department: current_user.org_department))

    if client.save
      redirect_to client_path(client), notice: "Added #{client.name}."
    else
      redirect_back fallback_location: clients_path, alert: client.errors.full_messages.to_sentence
    end
  end

  private

  def client_params
    params.require(:client).permit(:name, :notes, :active)
  end
end

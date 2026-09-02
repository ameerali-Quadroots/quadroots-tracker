class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("task_manager") }

  def create
    client = Client.new(client_params.merge(department_id: current_user.department_id))

    if client.save
      redirect_to dashboard_tasks_path(tab: "sprints"), notice: "Client created."
    else
      redirect_to dashboard_tasks_path(tab: "sprints"), alert: client.errors.full_messages.to_sentence
    end
  end

  private

  def client_params
    params.require(:client).permit(:name, :notes, :active)
  end
end

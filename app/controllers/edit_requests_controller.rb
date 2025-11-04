class EditRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_edit_request, only: [:approve, :reject]

  def create
  @edit_request = current_user.edit_requests.new(edit_request_params)

  # Check if the requested_clock_in falls within any time_clock range for this user
 time_clock_exists = TimeClock.where(user_id: current_user.id)
                             .where("clock_in <= ?", @edit_request.requested_clock_in)
                             .exists?


  unless time_clock_exists
    return redirect_back fallback_location: root_path, 
                         alert: "No matching time record found for the requested clock-in time."
  end

  if @edit_request.save
    EditRequestMailer.new_request_notification(@edit_request).deliver_later
    redirect_back fallback_location: root_path, notice: "Request submitted successfully."
  else
    redirect_back fallback_location: root_path, alert: @edit_request.errors.full_messages.to_sentence
  end
end



  def index
  @edit_requests = EditRequest.all

  # Apply filters based on user input
  if params[:name].present?
    @edit_requests = @edit_requests.joins(:user).where("users.name ILIKE ?", "%#{params[:name]}%")
  end

  if params[:request_type].present?
    @edit_requests = @edit_requests.where(request_type: params[:request_type])
  end

  if params[:status].present? && params[:status] != 'all'
    @edit_requests = @edit_requests.where(status: params[:status])
  end

  # Apply sorting
  if params[:sort_by].present? && params[:sort_order].present?
    sort_column = params[:sort_by]
    sort_direction = params[:sort_order] == 'desc' ? 'desc' : 'asc'
    @edit_requests = @edit_requests.order("#{sort_column} #{sort_direction}")
  end

  # Filtering by department and user
  if current_user.role == "Manager" && current_user.department != "HOD'S"
    @edit_requests = @edit_requests.where(department: current_user.department)
                                    .where.not(user_id: current_user.id)
  elsif current_user.department == "HOD'S"
    departments = ["WEB", "SEO", "ADS", "CONTENT"]
    manager_ids = User.where(role: "Manager", department: departments).pluck(:id)
    @edit_requests = @edit_requests.where(user_id: manager_ids)
  else
    @edit_requests = EditRequest.none
  end
end



  def approve
    @edit_request.update(
      approved_by_manager: "yes",
    )
    redirect_back fallback_location: edit_requests_path, notice: "Request approved successfully."
  end

  def reject
    @edit_request.update(
      approved_by_manager: "no",
    )
    redirect_back fallback_location: edit_requests_path, notice: "Request rejected."
  end

  def my_requests
    @edit_requests = current_user.edit_requests
  end

  private

  def set_edit_request
    @edit_request = EditRequest.find(params[:id])
  end

  def edit_request_params
    params.require(:edit_request).permit(:name, :email, :time_clock_id, :requested_clock_in, :reason, :department, :request_type,:break_reason)
  end
end

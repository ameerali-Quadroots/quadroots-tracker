class EditRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_edit_request, only: [:approve, :reject]

  def create
  @edit_request = current_user.edit_requests.new(edit_request_params)

  # Check if the requested_clock_in falls within any time_clock range for this user
  time_clock_exists = TimeClock.where(user_id: current_user.id)
                               .where("clock_in <= ? AND clock_out >= ?", 
                                      @edit_request.requested_clock_in, 
                                      @edit_request.requested_clock_in)
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
    @edit_requests = EditRequest.where(department: current_user.department)
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

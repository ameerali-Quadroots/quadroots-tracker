class EditRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_edit_request, only: [:approve, :reject]

  def create
    @edit_request = current_user.edit_requests.new(edit_request_params)

    if @edit_request.time_clock_id.blank?
      return redirect_back fallback_location: root_path, alert: "No time clock specified."
    end

    unless current_user.time_clocks.exists?(id: @edit_request.time_clock_id)
      return redirect_back fallback_location: root_path, alert: "No matching time record found for this user."
    end

    if @edit_request.requested_clock_in.blank?
      return redirect_back fallback_location: root_path, alert: "Requested date/time is required."
    end

    if @edit_request.save
      NotificationService.notify_edit_request(@edit_request)
      redirect_back fallback_location: root_path, notice: "Request submitted successfully."
    else
      redirect_back fallback_location: root_path, alert: @edit_request.errors.full_messages.to_sentence
    end
  end

  def index
    @edit_requests = EditRequest.all

    @edit_requests = @edit_requests.joins(:user).where("users.name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    @edit_requests = @edit_requests.where(request_type: params[:request_type]) if params[:request_type].present?
    @edit_requests = @edit_requests.where(status: params[:status]) if params[:status].present? && params[:status] != 'all'

    if current_user.role == "Manager" && current_user.department != "HOD'S"
      @edit_requests = @edit_requests.where(department: current_user.department)
                                     .where.not(user_id: current_user.id)
    elsif current_user.department == "HOD'S"
      manager_ids = User.where(role: "Manager", department: ["WEB", "SEO", "ADS", "CONTENT"]).pluck(:id)
      @edit_requests = @edit_requests.where(user_id: manager_ids)
    else
      @edit_requests = EditRequest.none
    end

    if params[:sort_by].present? && params[:sort_order].present?
      sort_direction = params[:sort_order] == 'desc' ? 'desc' : 'asc'
      @edit_requests = @edit_requests.order("#{params[:sort_by]} #{sort_direction}")
    else
      @edit_requests = @edit_requests.order(created_at: :desc)
    end
  end

  def approve
    return redirect_back(fallback_location: edit_requests_path, alert: manager_window_message) unless @edit_request.manager_actionable?

    @edit_request.update(approved_by_manager: true)
    redirect_back fallback_location: edit_requests_path, notice: "Request approved successfully."
  end

  def reject
    return redirect_back(fallback_location: edit_requests_path, alert: manager_window_message) unless @edit_request.manager_actionable?

    @edit_request.update(approved_by_manager: false)
    redirect_back fallback_location: edit_requests_path, notice: "Request rejected."
  end

  def my_requests
    @edit_requests = current_user.edit_requests

    @edit_requests = @edit_requests.where(status: params[:status]) if params[:status].present?
    @edit_requests = @edit_requests.where(request_type: params[:request_type]) if params[:request_type].present?

    if params[:from_date].present? && params[:to_date].present?
      from = Date.parse(params[:from_date]).beginning_of_day
      to   = Date.parse(params[:to_date]).end_of_day
      @edit_requests = @edit_requests.where(created_at: from..to)
    end

    @edit_requests = @edit_requests.order(created_at: :desc)
  end

  private

  def set_edit_request
    @edit_request = EditRequest.find(params[:id])
  end

  def manager_window_message
    "This request is more than a week old and can no longer be approved or rejected."
  end

  def edit_request_params
    params.require(:edit_request).permit(:name, :email, :time_clock_id, :requested_clock_in, :reason, :department, :request_type, :break_reason)
  end
end

class EditRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_edit_request, only: [:approve, :reject]

  def create
    @edit_request = current_user.edit_requests.new(edit_request_params)

    if @edit_request.requested_clock_in.blank?
      return redirect_back fallback_location: root_path, alert: "Requested date/time is required."
    end

    # The shared modal always submits the *latest* time clock as `time_clock_id`,
    # regardless of which day the employee is actually correcting. Re-link the request
    # to the time clock that matches the date/time the employee entered, otherwise an
    # approval would overwrite an unrelated day's clock-in (e.g. a request to fix
    # June 11 would rewrite the June 15 record).
    target_time_clock = time_clock_for_requested_time(@edit_request.requested_clock_in)

    if target_time_clock.nil?
      return redirect_back fallback_location: root_path,
        alert: "No time record found for #{@edit_request.requested_clock_in.to_date.strftime('%b %d, %Y')}."
    end

    @edit_request.time_clock_id = target_time_clock.id

    if @edit_request.save
      NotificationService.notify_edit_request(@edit_request)
      redirect_back fallback_location: root_path, notice: "Request submitted successfully."
    else
      redirect_back fallback_location: root_path, alert: @edit_request.errors.full_messages.to_sentence
    end
  end

  def index
    @edit_requests = EditRequest.includes(:user, approvals: { approval_step: :role })

    @edit_requests = @edit_requests.joins(:user).where("users.name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    @edit_requests = @edit_requests.where(request_type: params[:request_type]) if params[:request_type].present?
    @edit_requests = @edit_requests.where(status: params[:status]) if params[:status].present? && params[:status] != 'all'

    # Scoped by the organogram rather than hardcoded department lists: you see
    # requests from anyone below you in the reporting tree. Whether you can
    # *act* on one is decided per request by EditRequest#actionable_by?.
    if can_view?("edit_requests.review")
      @edit_requests = @edit_requests.where(user_id: current_user.subordinate_ids)
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
    return redirect_back(fallback_location: edit_requests_path, alert: not_your_step_message) unless @edit_request.actionable_by?(current_user)

    @edit_request.approve!(by: current_user, note: params[:note])
    NotificationService.notify_edit_request_advanced(@edit_request)

    next_step = @edit_request.current_step
    notice = if next_step
               "Approved. Now waiting on #{next_step}."
             else
               "Approved. This was the final step, so the change has been applied."
             end
    redirect_back fallback_location: edit_requests_path, notice: notice
  end

  def reject
    return redirect_back(fallback_location: edit_requests_path, alert: manager_window_message) unless @edit_request.manager_actionable?
    return redirect_back(fallback_location: edit_requests_path, alert: not_your_step_message) unless @edit_request.actionable_by?(current_user)

    @edit_request.reject!(by: current_user, note: params[:note])
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

  # Finds the current user's time clock that the requested time actually belongs to,
  # so an edit request corrects the right day instead of the most recent record.
  # Looks within a 3-day window (to cover night shifts that span midnight) and:
  #   1. prefers the shift whose clock_in..clock_out range contains the requested time
  #      (correct for break edits, which land in the middle of a shift), then
  #   2. falls back to the record clocked in on the same calendar day, closest in time.
  def time_clock_for_requested_time(requested_time)
    window = (requested_time.to_date - 1.day).beginning_of_day..(requested_time.to_date + 1.day).end_of_day
    clocks = current_user.time_clocks.where(clock_in: window).order(clock_in: :desc).to_a

    within_shift = clocks.detect do |tc|
      tc.clock_in.present? && tc.clock_out.present? && (tc.clock_in..tc.clock_out).cover?(requested_time)
    end
    return within_shift if within_shift

    clocks
      .select { |tc| tc.clock_in&.to_date == requested_time.to_date }
      .min_by { |tc| (tc.clock_in - requested_time).abs }
  end

  def set_edit_request
    @edit_request = EditRequest.find(params[:id])
  end

  def manager_window_message
    "This request is more than a week old and can no longer be approved or rejected."
  end

  def not_your_step_message
    step = @edit_request.current_step
    return "This request has already been fully processed." if step.nil?

    "This request is waiting on #{step}, not you."
  end

  def edit_request_params
    params.require(:edit_request).permit(:name, :email, :time_clock_id, :requested_clock_in, :reason, :department, :request_type, :break_reason)
  end
end

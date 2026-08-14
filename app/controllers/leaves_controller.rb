class LeavesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_leave, only: [:approve, :reject]

  def index
    # Scoped by the organogram rather than hardcoded department lists: you
    # review leaves for anyone below you in the reporting tree.
    @leaves = if can_view?("leaves.review")
                Leave.includes(:user)
                     .where(user_id: current_user.subordinate_ids)
                     .order(created_at: :desc)
              else
                Leave.none
              end
  end

  def my_leaves
    @leaves = current_user.leaves

    @leaves = @leaves.where(status: params[:status]) if params[:status].present?
    @leaves = @leaves.where(leave_type: params[:leave_type]) if params[:leave_type].present?

    if params[:from_date].present? && params[:to_date].present?
      from = Date.parse(params[:from_date])
      to   = Date.parse(params[:to_date])
      @leaves = @leaves.where(start_date: from..to)
    end

    @leaves = @leaves.order(created_at: :desc)
  end

  def new
    @leave = current_user.leaves.new
  end

  def create
    @leave = current_user.leaves.new(leave_params)
    @leave.status  = 'pending'
    @leave.user_id = params[:leave][:user_id] || current_user.id

    if @leave.save
      NotificationService.notify_leave_request(@leave)
      redirect_to root_path, notice: 'Leave request submitted for approval.'
    else
      redirect_to root_path, alert: 'Failed to submit leave request.'
    end
  end

  def approve
    return redirect_back(fallback_location: leaves_path, alert: not_your_step_message) unless @leave.actionable_by?(current_user)

    @leave.approve!(by: current_user, note: params[:note])

    next_step = @leave.current_step
    notice = next_step ? "Approved. Now waiting on #{next_step}." : "Approved."
    redirect_to request.referer, notice: notice
  end

  def reject
    return redirect_back(fallback_location: leaves_path, alert: not_your_step_message) unless @leave.actionable_by?(current_user)

    @leave.reject!(by: current_user, note: params[:note])
    redirect_to request.referer, alert: 'Leave rejected.'
  end

  # Admin-panel style override: settles every remaining step in one action,
  # mirroring EditRequest#force_approve! / #force_reject!.
  def approve_by_admin
    @leave = Leave.find(params[:id])
    @leave.force_approve!(by: current_user, note: params[:note])
    redirect_to request.referer, notice: 'Leave approved.'
  end

  def reject_by_admin
    @leave = Leave.find(params[:id])
    @leave.force_reject!(by: current_user, note: params[:note])
    redirect_to request.referer, alert: 'Leave rejected.'
  end

  private

  def set_leave
    @leave = Leave.find(params[:id])
  end

  def leave_params
    params.require(:leave).permit(:leave_type, :start_date, :end_date, :reason, :approved_by_manager, :medical_certificate)
  end

  def not_your_step_message
    step = @leave.current_step
    return "This request has already been fully processed." if step.nil?

    "This request is waiting on #{step}, not you."
  end
end

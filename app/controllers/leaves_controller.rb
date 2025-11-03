class LeavesController < ApplicationController
  before_action :set_leave, only: [:approve, :reject]
  before_action :authenticate_user!

  def index
  if current_user.role == "Manager" && current_user.department != "HOD'S"
    @leaves = Leave.joins(:user)
                   .where(users: { role: "Executive", department: current_user.department })
                   .order(created_at: :desc)

  elsif current_user.role == "Manager" && current_user.department == "HOD'S"
    # HOD manager: sees executives from specific departments
    hod_departments = ["WEB", "SEO", "ADS", "CONTENT"]

    @leaves = Leave.joins(:user)
                   .where(users: { role: "Manager", department: hod_departments })
                   .order(created_at: :desc)

  else
    # Default fallback (optional)
    @leaves = Leave.none
  end
end
  def new
    @leave = current_user.leaves.new
  end

  def create
    @leave = current_user.leaves.new(leave_params)
    @leave.status = 'pending'
    user_id = params[:leave][:user_id] || current_user.id 
    @leave.user_id = user_id
    if @leave.save
      redirect_to root_path, notice: 'Leave request submitted for approval.'
    else
    redirect_to root_path, alert: "Failed to submit leave request."
    end
  end

  def approve
    @leave.update(approved_by_manager: 'true')
    redirect_to request.referer, notice: 'Leave approved.'
  end

  def reject
    @leave.update(approved_by_manager: 'false')
  redirect_to request.referer, alert: 'Leave rejected.'
  end


   def approve_by_admin
    @leave = Leave.find(params[:id])
    @leave.update(status: 'approved')
    redirect_to request.referer, notice: 'Leave approved.'
  end

  def reject_by_admin
    @leave = Leave.find(params[:id])
    @leave.update(status: 'rejected')
  redirect_to request.referer alert: 'Leave rejected.'
  end

  private

  def set_leave
    @leave = Leave.find(params[:id])
  end

  def leave_params
    params.require(:leave).permit(:leave_type, :start_date, :end_date, :reason, :approved_by_manager, :medical_certificate)
  end
end

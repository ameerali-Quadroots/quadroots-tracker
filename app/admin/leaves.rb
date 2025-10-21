ActiveAdmin.register Leave do
  permit_params :user_id, :leave_type, :start_date, :end_date, :reason, :status, :approved_by

  index do
    selectable_column
    id_column
    column :user
    column :leave_type
    column :start_date
    column :end_date
    column :status

    column "Medical Leaves (Approved)" do |leave|
      leave.user.medical_leaves_count
    end

    column "Casual Leaves (Approved)" do |leave|
      leave.user.casual_leaves_count
    end

    column "Remaining Medical Leaves" do |leave|
      leave.user.remaining_medical_leaves
    end

    column "Remaining Casual Leaves" do |leave|
      leave.user.remaining_casual_leaves
    end

    column "Absent Days" do |leave|
      leave.user.absent_days_count
    end

    actions defaults: true do |leave|
  if leave.pending?
    div class: "d-flex gap-2 justify-content-center" do
      span do
        link_to "Approve", approve_by_admin_leave_path(leave), 
          method: :patch, 
          class: "btn btn-success btn-sm"
      end
      span do
        link_to "Reject", reject_by_admin_leave_path(leave), 
          method: :patch, 
          class: "btn btn-danger btn-sm"
      end
    end
  end
end
  end

  member_action :approve, method: :patch do
    resource.update(status: "approved", approved_by: current_user.id)
    redirect_back fallback_location: admin_leaves_path, notice: "Leave approved successfully."
  end

  member_action :reject, method: :patch do
    resource.update(status: "rejected", approved_by: current_user.id)
    redirect_back fallback_location: admin_leaves_path, alert: "Leave rejected."
  end
end

ActiveAdmin.register Leave do
  # Permit only the fields that exist in your schema
  permit_params :user_id, :leave_type, :start_date, :end_date, :reason, :status, :approved_by_manager

  # INDEX PAGE
  index do
    selectable_column
    id_column
    column :user
    column :leave_type
    column :start_date
    column :end_date
    column :status


    actions defaults: true do |leave|
      if leave.status == "pending"
        div class: "d-flex gap-2 justify-content-center" do
          span do
            link_to "Approve", approve_admin_leave_path(leave),
              method: :patch,
              class: "btn btn-success btn-sm"
          end
          span do
            link_to "Reject", reject_admin_leave_path(leave),
              method: :patch,
              class: "btn btn-danger btn-sm"
          end
        end
      end
    end
  end

  # SHOW PAGE
  show do
    attributes_table do
      row :id
      row :user
      row :leave_type
      row :start_date
      row :end_date
      row :reason
      row :status
      row :approved_by_manager
      row :created_at
      row :updated_at
    end

    panel "User Leave Summary" do
      attributes_table_for leave.user do
        row("Medical Leaves (Approved)") { leave.user.medical_leaves_count }
        row("Casual Leaves (Approved)") { leave.user.casual_leaves_count }
        row("Half Days (Approved)") { leave.user.half_days_count }
        row("Remaining Medical Leaves") { leave.user.remaining_medical_leaves }
        row("Remaining Casual Leaves") { leave.user.remaining_casual_leaves }
        row("Absent Days") { leave.user.absent_days_count }
      end
    end
  end

  # NEW / EDIT FORM
  form do |f|
    f.semantic_errors

    f.inputs "Leave Details" do
      f.input :user, collection: User.all.map { |u| [u.email, u.id] }, include_blank: false
      f.input :leave_type, as: :select, collection: ["medical", "casual", "half_day"], include_blank: false
      f.input :start_date, as: :datepicker
      f.input :end_date, as: :datepicker
      f.input :reason
      f.input :status, as: :select, collection: ["pending", "approved", "rejected"], include_blank: false
      f.input :approved_by_manager
    end

    f.actions
  end

  # CUSTOM ACTIONS
  member_action :approve, method: :patch do
    resource.update(status: "approved", approved_by_manager: true)
    redirect_back fallback_location: admin_leaves_path, notice: "Leave approved successfully."
  end

  member_action :reject, method: :patch do
    resource.update(status: "rejected", approved_by_manager: false)
    redirect_back fallback_location: admin_leaves_path, alert: "Leave rejected."
  end
end

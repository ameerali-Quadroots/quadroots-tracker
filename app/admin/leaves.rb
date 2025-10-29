ActiveAdmin.register Leave do
  # ✅ Permit parameters (including file attachment)
  permit_params :user_id, :leave_type, :start_date, :end_date, :reason, :status, :approved_by_manager, :medical_certificate

  # ✅ Default sorting
  config.sort_order = 'created_at_desc'

  # ✅ Scopes
  scope :all, default: true
  scope("Pending")  { |r| r.where(status: 'pending') }
  scope("Approved") { |r| r.where(status: 'approved') }
  scope("Rejected") { |r| r.where(status: 'rejected') }
  scope("Medical") { |r| r.where(leave_type: 'medical') }
  scope("Casual") { |r| r.where(leave_type: 'casual') }


  # ✅ Filters
  filter :user, collection: -> { User.all.map { |u| [u.name, u.id] } }, label: "User (Email)"
  filter :status, as: :select, collection: ["pending", "approved", "rejected"], label: "Status"
  filter :leave_type, as: :select, collection: ["medical", "casual", "half_day"], label: "Leave Type"
  filter :created_at, label: "Created At"
  filter :start_date
  filter :end_date

  # ✅ INDEX PAGE
  index do
    selectable_column
    id_column
    column("User") { |leave| leave.user&.email || "N/A" }
    column :leave_type
    column :start_date
    column :end_date
    column :approved_by_manager

    column :medical_certificate do |leave|
      if leave.medical_certificate.attached?
        link_to "View", rails_blob_path(leave.medical_certificate, disposition: "inline"), target: "_blank"
      else
        status_tag "No", class: "status-error"
      end
    end

    column :status do |leave|
      css_class = case leave.status
                  when "approved" then "status-ok"
                  when "rejected" then "status-error"
                  when "pending"  then "status-warning"
                  else "status-default"
                  end
      status_tag(leave.status.titleize, class: css_class)
    end

    column :created_at

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

  # ✅ SHOW PAGE
  show do
    attributes_table do
      row :id
      row("User") { leave.user&.email || "N/A" }
      row :leave_type
      row :start_date
      row :end_date
      row :reason
      row :status
      row :approved_by_manager

      row :medical_certificate do
        if leave.medical_certificate.attached?
          ext = leave.medical_certificate.filename.extension.downcase
          if %w[jpg jpeg png gif].include?(ext)
            link_to image_tag(url_for(leave.medical_certificate), style: "max-width: 250px; border-radius: 8px;"), 
                    rails_blob_path(leave.medical_certificate, disposition: "inline"), target: "_blank"
          else
            link_to "View Medical Certificate", rails_blob_path(leave.medical_certificate, disposition: "inline"), target: "_blank"
          end
        else
          status_tag "No", class: "status-error"
        end
      end

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

  # ✅ FORM
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

      f.input :medical_certificate, as: :file, hint: (
        f.object.medical_certificate.attached? ?
          link_to("View Current Certificate", rails_blob_path(f.object.medical_certificate, disposition: "inline"), target: "_blank") :
          "Upload medical certificate if leave type is Medical"
      )
    end

    f.actions
  end

  # ✅ CUSTOM ACTIONS
  member_action :approve, method: :patch do
    resource.update(status: "approved", approved_by_manager: true)
    redirect_back fallback_location: admin_leaves_path, notice: "Leave approved successfully."
  end

  member_action :reject, method: :patch do
    resource.update(status: "rejected", approved_by_manager: false)
    redirect_back fallback_location: admin_leaves_path, alert: "Leave rejected."
  end
end

ActiveAdmin.register EditRequest do
  # ✅ Menu options (optional)
  menu label: "Edit Requests", priority: 2

  # ✅ Allowed fields for form updates
  permit_params :name, :email, :requested_clock_in, :reason, :status, :resolved_at, :time_clock_id

  # ✅ Scope filters (optional tabs)
  scope :all, default: true
  scope("Pending")  { |r| r.where(status: 'pending') }
  scope("Approved") { |r| r.where(status: 'approved') }
  scope("Rejected") { |r| r.where(status: 'rejected') }

  # ✅ Index table view
  index title: "Edit Requests" do
    selectable_column
    column :name do |name|
      name.user.name
    end
    column :email do |name|
      name.user.email
    end
    column :department do |dep|
      dep.user.department
    end
    column :request_type    
    column :break_reason    
    column :requested_clock_in do |r|
      r.requested_clock_in&.strftime("%b %d, %Y %I:%M %p")
    end
    column :reason do |r|
      truncate(r.reason, length: 60)
    end
    column :status do |r|
      css_class = case r.status
                  when "approved" then "ok"
                  when "rejected" then "error"
                  when "pending"  then "warning"
                  else "default"
                  end
      status_tag r.status.capitalize, class: css_class
    end
  column :approved_by_manager do |r|
  if r.approved_by_manager
    status_tag "Yes", class: "ok"     # ✅ Green
  else
    status_tag "No", class: "error"   # ❌ Red
  end

end


    column :created_at do |r|
      r.created_at.strftime("%b %d, %Y %I:%M %p")
    end
    column :resolved_at do |r|
      r.resolved_at ? r.resolved_at.strftime("%b %d, %Y %I:%M %p") : "-"
    end

    actions defaults: true do |r|
      if !r.approved_by_admin
        span do
          link_to "✅ Approve", approve_admin_edit_request_path(r), method: :patch,
            class: "member_link green", data: { confirm: "Approve this request?" }
        end
        span do
          link_to "❌ Reject", reject_admin_edit_request_path(r), method: :patch,
            class: "member_link red", data: { confirm: "Reject this request?" }
        end
      else
        span "—", class: "text-muted"
      end
    end
  end

  # ✅ Show (detail) view
  show title: proc { |r| "Edit Request ##{r.id}" } do
    attributes_table do
      row :id
      row :time_clock
      row :requested_clock_in do |r|
        r.requested_clock_in&.strftime("%b %d, %Y %I:%M %p")
      end
      row :reason do |r|
        simple_format r.reason
      end
      row :status do |r|
        css_class = case r.status
                    when "approved" then "ok"
                    when "rejected" then "error"
                    when "pending"  then "warning"
                    else "default"
                    end
        status_tag r.status.capitalize, class: css_class
      end
      row :approved_by_manager do |r|
        r.approved_by_manager? ? "Yes" : "No"
      end
      row :created_at
      row :resolved_at
    end

    # if !resource.approved_by_admin
    #   panel "Actions" do
    #     div class: "action-buttons" do
    #       span do
    #         link_to "✅ Approve", approve_admin_edit_request_path(resource), method: :patch,
    #           class: "button green", data: { confirm: "Approve this request?" }
    #       end
    #       span do
    #         link_to "❌ Reject", reject_admin_edit_request_path(resource), method: :patch,
    #           class: "button red", data: { confirm: "Reject this request?" }
    #       end
    #     end
    #   end
    # end
  end

  # ✅ Form (create/edit)
  form do |f|
    f.semantic_errors
    f.inputs "Edit Request Details" do
      f.input :time_clock
      f.input :break_reason
     f.input :requested_clock_in, as: :datetime_picker
      f.input :reason
      f.input :status, as: :select, collection: %w[pending approved rejected]
      f.input :resolved_at, as: :datetime_picker
    end
    f.actions
  end

  # ✅ Custom Approve action
  member_action :approve, method: :patch do
    if resource.requested_clock_in.present? 
      if resource.time_clock.present? && resource.request_type == "Clock tower not working"
        resource.time_clock.update(clock_in: resource.requested_clock_in, status: "on_time" )
      end
      if resource.time_clock.present? && resource.request_type == "Forgot to end break"  || resource.request_type == "Forgot to add break"
        resource.time_clock.breaks.where(break_type: resource.break_reason).update(break_out: resource.requested_clock_in)
        
     end


      resource.update(status: "approved", resolved_at: Time.current, approved_by_admin: true)
      redirect_to collection_path, notice: "Request approved and time clock updated."
    else

      redirect_to collection_path, alert: "No requested clock-in time present."
    end
  end

  # ✅ Custom Reject action
  member_action :reject, method: :patch do
    resource.update(status: "rejected", resolved_at: Time.current)
    redirect_to collection_path, notice: "Request rejected."
  end
end

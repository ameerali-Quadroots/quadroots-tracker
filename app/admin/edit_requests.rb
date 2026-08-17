ActiveAdmin.register EditRequest do
  # ✅ Menu options (optional)
  menu label: "Edit Requests", priority: 4

  # ✅ Allowed fields for form updates
  permit_params :name, :email, :requested_clock_in, :reason, :status, :resolved_at, :time_clock_id



    filter :user_name, as: :string, label: 'Employee Name'



  # ✅ Scope filters (optional tabs)
  scope :all, default: true
  scope("Pending")  { |r| r.where(status: 'pending') }
  scope("Approved") { |r| r.where(status: 'approved') }
  scope("Rejected") { |r| r.where(status: 'rejected') }
  scope("Clock Tower not working") { |r| r.where(request_type: 'Clock tower not working') }
  scope("Forget to Add Break") { |r| r.where(request_type: 'Forgot to add break') }
  scope("Forget to End Break") { |r| r.where(request_type: 'Forgot to end break') }

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

    actions defaults: false do |r|
      span do
        link_to "View", admin_edit_request_path(r), class: "member_link view_link"
      end
      span do
        link_to "Delete", admin_edit_request_path(r), method: :delete,
          class: "member_link delete_link", data: { confirm: "Are you sure you want to delete this?" }
      end

      step = r.current_step
      if step.nil?
        span "—", class: "text-muted"
      else
        # Approve only once the chain has actually reached the admin step (i.e.
        # the manager - and any step before the admin - has already signed
        # off). Reject stays available regardless, so a bad request can still
        # be stopped while it's waiting on someone else.
        if step.admin_step?
          span do
            link_to "✅ Approve", approve_admin_edit_request_path(r), method: :patch,
              class: "member_link green", data: { confirm: "Approve this request?" }
          end
        end
        span do
          link_to "❌ Reject", reject_admin_edit_request_path(r), method: :patch,
            class: "member_link red", data: { confirm: "Reject this request?" }
        end
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
      row("Waiting on") do |r|
        step = r.current_step
        if step.nil?
          "Nothing — chain complete"
        elsif step.admin_step?
          "#{step} — approve or reject from this page"
        else
          approver = r.current_approver
          "#{step}#{approver ? " — #{approver.name}" : ' (nobody above the requester holds this role)'}"
        end
      end
    end

    panel "Approval chain" do
      if resource.approvals.empty?
        para "No approval flow matched this request. Configure one under Settings → Approval Flows."
      else
        table_for resource.approvals.ordered do
          column("#") { |a| a.position + 1 }
          column("Step") { |a| a.role_name }
          column("Status") do |a|
            css = { "approved" => "ok", "rejected" => "error", "pending" => "warning" }[a.status] || "default"
            status_tag a.status.capitalize, class: css
          end
          column("Approver") { |a| a.approver.try(:name) || a.approver.try(:email) || "—" }
          column("When") { |a| a.acted_at&.strftime("%b %d, %Y %I:%M %p") || "—" }
          column("Note") { |a| a.note }
        end
      end
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
  # Admin override: settles every remaining step in the chain at once and
  # applies the correction to the time clock (EditRequest#apply_to_time_clock!).
  # Blocked until the chain has reached the admin step - a manager (and any
  # step ahead of the admin) must have already approved.
  member_action :approve, method: :patch do
    if resource.requested_clock_in.blank?
      redirect_back(fallback_location: collection_path, alert: "No requested clock-in time present.")
      next
    end

    step = resource.current_step
    unless step.nil? || step.admin_step?
      redirect_back(fallback_location: collection_path, alert: "This request is still waiting on #{step} - it can't be approved until they act.")
      next
    end

    skipped = resource.approvals.pending.count
    resource.force_approve!(by: current_admin_user, note: "Approved from the admin panel.")

    notice = "Request approved and time clock updated."
    notice += " #{skipped} outstanding approval step(s) were signed off." if skipped.positive?
    redirect_back(fallback_location: collection_path, notice: notice)
  end

  # ✅ Reject action
  member_action :reject, method: :patch do
    resource.force_reject!(by: current_admin_user, note: "Rejected from the admin panel.")
    redirect_back(fallback_location: collection_path, notice: "Request rejected.")
  end

end

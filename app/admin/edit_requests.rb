ActiveAdmin.register EditRequest do
  # ✅ Menu options (optional)
  menu label: "Edit Requests", priority: 4

  # ✅ Allowed fields for form updates
  # Every real column is editable from the admin form - a super admin (or any
  # role granted Update on EditRequest) can correct anything on a request,
  # including who it belongs to and which shift it points at.
  permit_params :user_id, :time_clock_id, :request_type, :break_reason,
                :requested_clock_in, :reason, :department, :status,
                :manager_note, :approved_by_manager, :approved_by_admin,
                :resolved_at

  # ✅ Filters - one per editable/reportable attribute
  filter :id, as: :numeric, label: "Request ID"
  filter :user, collection: -> { User.order(:name).pluck(:name, :id) }, label: "Employee"
  filter :user_name, as: :string, label: "Employee Name"
  filter :user_email, as: :string, label: "Employee Email"
  filter :department, as: :select,
                      collection: -> { Department.order(:name).pluck(:name) },
                      label: "Department"
  filter :request_type, as: :select, collection: -> { EditRequest::REQUEST_TYPES }
  filter :break_reason, as: :select, collection: -> { Break::VALID_BREAK_TYPES }
  filter :status, as: :select, collection: -> { EditRequest.statuses.keys }
  filter :approved_by_manager, as: :select, collection: -> { [["Yes", true], ["No", false]] }
  filter :approved_by_admin, as: :select, collection: -> { [["Yes", true], ["No", false]] }
  filter :reason, as: :string
  filter :manager_note, as: :string
  filter :time_clock_id, as: :numeric, label: "Time Clock ID"
  filter :requested_clock_in
  filter :created_at
  filter :resolved_at
  filter :updated_at


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
    column "Employee" do |r|
      div class: "cell-user" do
        span r.user.name.to_s.split.first(2).map { |part| part[0] }.join.upcase, class: "cell-user-avatar"
        div class: "cell-user-text" do
          span r.user.name, class: "cell-user-name"
          span r.user.email, class: "cell-user-sub"
        end
      end
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
      # Shown to anyone CanCan grants Update on EditRequest (super admins
      # always; other roles when the permission matrix says so). `actions
      # defaults: false` above drops ActiveAdmin's built-in Edit link, so it
      # has to be rendered here.
      if authorized?(:update, r)
        span do
          link_to "Edit", edit_admin_edit_request_path(r), class: "member_link edit_link"
        end
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
          column("Approver") { |a| a.approver_name || "—" }
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
  # Everything on the record is editable here. The model's week/monthly-limit
  # validations only run `on: :create`, so an admin correcting an old request
  # is not blocked by them.
  form do |f|
    f.semantic_errors

    # The full TimeClock list is far too large for a dropdown, so scope it to
    # the requester's own shifts once the request has an owner. The currently
    # linked shift is always kept in the list so an edit can never silently
    # re-point the request at a different day.
    clocks = f.object.user ? f.object.user.time_clocks.order(clock_in: :desc) : TimeClock.order(clock_in: :desc).limit(200)
    clock_options = (clocks.to_a + [f.object.time_clock]).compact.uniq.map do |tc|
      ["##{tc.id} - #{tc.clock_in&.strftime('%b %d, %Y %I:%M %p') || 'no clock-in'}", tc.id]
    end

    f.inputs "Employee" do
      f.input :user, collection: User.order(:name).map { |u| ["#{u.name} (#{u.email})", u.id] }, include_blank: false
      f.input :department, as: :select,
                           collection: Department.order(:name).pluck(:name),
                           include_blank: "-- none --"
    end

    f.inputs "Edit Request Details" do
      f.input :time_clock, collection: clock_options, include_blank: false
      f.input :request_type, as: :select, collection: EditRequest::REQUEST_TYPES, include_blank: false
      f.input :break_reason, as: :select, collection: Break::VALID_BREAK_TYPES,
                             include_blank: "-- not a break edit --",
                             hint: "Only used by the 'Forgot to add/end break' types."
      f.input :requested_clock_in, as: :datetime_picker
      f.input :reason
    end

    f.inputs "Approval" do
      f.input :status, as: :select, collection: EditRequest.statuses.keys, include_blank: false,
                       hint: "Setting this by hand only changes the record - it does not run the approval chain or update the time clock. Use the Approve / Reject buttons for that."
      f.input :approved_by_manager
      f.input :approved_by_admin
      f.input :manager_note
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

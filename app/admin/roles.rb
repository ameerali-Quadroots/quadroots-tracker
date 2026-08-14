ActiveAdmin.register Role do
  menu parent: "Settings", label: "Roles & Permissions", priority: 1

  permit_params :name, :scope, :rank, :description, :active, permission_ids: []

  filter :name
  filter :scope, as: :select, collection: Role::SCOPES
  filter :active

  index do
    selectable_column
    column :name do |role|
      div do
        strong role.name
        span " SYSTEM", class: "role-system-flag" if role.system?
      end
      small role.description, class: "role-desc" if role.description.present?
    end
    column :scope do |role|
      status_tag role.scope, class: (role.scope == "admin" ? "orange" : "blue")
    end
    column("Seniority", :rank)
    column "Members" do |role|
      role.member_count
    end
    column "Permissions" do |role|
      "#{role.permissions.resources.count} resource / #{role.permissions.pages.count} page"
    end
    column :active
    # Delete is hidden where the model would refuse it anyway.
    actions defaults: false do |role|
      links = [
        link_to("View", admin_role_path(role), class: "member_link"),
        link_to("Edit", edit_admin_role_path(role), class: "member_link")
      ]
      unless role.system? || role.member_count.positive?
        links << link_to("Delete", admin_role_path(role), class: "member_link",
                         method: :delete, data: { confirm: "Delete the #{role.name} role?" })
      end
      safe_join(links, " ")
    end
  end

  show do
    attributes_table do
      row :name
      row :slug
      row :scope
      row("Seniority") { |r| r.rank }
      row :description
      row :system
      row :active
      row("Members") { |r| r.member_count }
    end

    panel "Permissions" do
      render partial: "admin/roles/permission_summary", locals: { role: resource }
    end
  end

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "Role" do
      f.input :name, hint: "Shown throughout the app, e.g. \"HOD\" or \"CEO\"."
      f.input :scope, as: :select, collection: Role::SCOPES, include_blank: false,
              hint: "employee = the tracker app, admin = the admin panel, both = either."
      f.input :rank, label: "Seniority",
              hint: "Lower is more senior. Orders the organogram (CEO 5, Manager 40, Executive 60)."
      f.input :description, input_html: { rows: 2 }
      f.input :active
    end

    f.inputs "Permissions" do
      render partial: "admin/roles/permission_matrix", locals: { f: f, role: f.object }
    end

    f.actions
  end

  controller do
    def update
      # A system role's permissions are fixed; ignore any tampering with them.
      params[:role]&.delete(:permission_ids) if resource.system?
      super
    end

    def destroy
      if resource.member_count.positive?
        redirect_to collection_path,
                    alert: "#{resource.name} still has #{resource.member_count} member(s). Reassign them first."
        return
      end
      super
    end
  end
end

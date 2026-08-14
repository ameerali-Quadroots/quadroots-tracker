ActiveAdmin.register Department do
  menu parent: "Settings", label: "Departments", priority: 2

  permit_params :name, :code, :position, :active

  filter :name
  filter :active

  index do
    selectable_column
    column :name
    column :code
    column("Employees") { |d| d.users.count }
    column("Admin users") { |d| d.admin_users.count }
    column("Order", :position)
    column :active
    actions
  end

  show do
    attributes_table do
      row :name
      row :code
      row :position
      row :active
      row("Employees") { |d| d.users.count }
      row("Admin users") { |d| d.admin_users.count }
    end

    panel "Members" do
      table_for department.users.includes(:access_role).order(:name) do
        column("Name") { |u| link_to u.name, admin_employee_path(u) }
        column("Role") { |u| u.access_role&.name || u[:role] }
        column :email
      end
    end
  end

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)
    f.inputs "Department" do
      f.input :name
      f.input :code, hint: "Optional short code."
      f.input :position, label: "Order", hint: "Lower appears first in dropdowns."
      f.input :active, hint: "Inactive departments stay on existing records but are hidden from dropdowns."
    end
    f.actions
  end

  controller do
    def destroy
      # Department#ensure_no_members aborts the delete; surface why.
      if resource.member_count.positive?
        redirect_to collection_path,
                    alert: "#{resource.name} still has #{resource.member_count} member(s). Move them first."
        return
      end
      super
    end
  end
end

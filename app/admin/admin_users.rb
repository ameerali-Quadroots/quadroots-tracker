ActiveAdmin.register AdminUser do
  menu label: "Admin Users", priority: 7

  controller do
    before_action :authorize_admin_user!

    def authorize_admin_user!
      authorize! :manage, AdminUser
    end
  end
  
  permit_params :email, :password, :password_confirmation, :role_id, :department_id, additional_department_ids: []

  index do
    selectable_column
    id_column
    column :email
    column("Role") { |a| a.access_role&.name || a[:role] }
    column("Department") { |a| a.org_department&.name || a[:department] }
    column("Additional Departments") { |a| a.additional_departments.map(&:name).join(", ") }
    actions
  end

  filter :email
  filter :access_role, as: :select, collection: -> { Role.for_scope(:admin).ordered.pluck(:name, :id) }, label: "Role"


  form do |f|
    f.inputs do
      f.input :email
      # Roles and departments are managed under Settings, not hardcoded here.
      f.input :role_id, as: :select, label: "Role",
        collection: Role.active.for_scope(:admin).ordered.pluck(:name, :id),
        prompt: "Select Role",
        input_html: { class: "dropdown", style: "width:50%" }
      f.input :department_id, as: :select, label: "Department",
        collection: Department.active.ordered.pluck(:name, :id),
        prompt: "Select Department",
        input_html: { class: "dropdown", style: "width:50%" }
      f.input :additional_department_ids, as: :check_boxes, label: "Additional Departments (view access)",
        collection: Department.active.ordered.pluck(:name, :id),
        hint: "Grants this admin visibility into these departments' Dashboard and Time Clocks data, in addition to their own Department above."
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end

end

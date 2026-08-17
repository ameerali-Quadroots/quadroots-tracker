require "csv"

ActiveAdmin.register TaskType do
  menu parent: "Settings", label: "Task Types", priority: 3

  permit_params :name, :department_id, :sla_minutes, :description

  filter :name
  filter :department

  action_item :bulk_upload, only: :index do
    link_to "Bulk Upload", admin_bulk_upload_task_types_path
  end

  index do
    selectable_column
    column :name
    column :department
    column("SLA") { |tt| tt.formatted_sla }
    column("Tasks") { |tt| tt.tasks.count }
    actions
  end

  show do
    attributes_table do
      row :name
      row :department
      row :sla_minutes
      row :description
    end
  end

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)
    f.inputs "Task Type" do
      f.input :department
      f.input :name
      f.input :sla_minutes, hint: "Default minutes before a task of this type is flagged over SLA. A manager can still override this per task when assigning it."
      f.input :description, hint: "Shown to the manager when they pick this type while assigning a task."
    end
    f.actions
  end

  controller do
    def destroy
      if resource.tasks.exists?
        redirect_to collection_path,
                    alert: "#{resource.name} still has tasks assigned against it. Reassign or remove them first."
        return
      end
      super
    end
  end
end

# A standalone custom page (not a collection_action) so the upload form gets
# ActiveAdmin's normal full-chrome page rendering — collection/member actions
# are plain controller actions in this app's minimal custom admin layout
# (app/views/layouts/active_admin_custom.html.erb has no header/sidebar of
# its own; only content-do pages built through ActiveAdmin's page pipeline
# get one). Kept out of the sidebar (menu false) — reached via the "Bulk
# Upload" action item on the Task Types index above.
ActiveAdmin.register_page "Bulk Upload Task Types" do
  menu false

  content title: "Bulk Upload Task Types" do
    render partial: "admin/task_types/bulk_upload_form"
  end

  page_action :import, method: :post do
    uploaded = params[:file]
    if uploaded.blank?
      redirect_to admin_bulk_upload_task_types_path, alert: "Please choose a CSV file."
      next
    end

    created = 0
    updated = 0
    errors = []
    row_number = 1 # header is row 1

    CSV.foreach(uploaded.path, headers: true) do |row|
      row_number += 1
      department = Department.find_by("LOWER(name) = ?", row["department"].to_s.strip.downcase)
      name = row["name"].to_s.strip

      if department.nil?
        errors << "Row #{row_number}: department '#{row['department']}' not found"
        next
      end
      if name.blank?
        errors << "Row #{row_number}: name is blank"
        next
      end

      task_type = TaskType.find_or_initialize_by(department: department, name: name)
      was_new = task_type.new_record?
      task_type.sla_minutes = row["sla_minutes"].to_i
      task_type.description = row["description"] if row["description"].present?

      if task_type.save
        was_new ? created += 1 : updated += 1
      else
        errors << "Row #{row_number}: #{task_type.errors.full_messages.to_sentence}"
      end
    end

    message = "Bulk upload complete — #{created} created, #{updated} updated."
    message += " Errors: #{errors.join('; ')}" if errors.any?
    redirect_to admin_task_types_path, notice: message
  end
end

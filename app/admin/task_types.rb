ActiveAdmin.register TaskType do
  menu parent: "Settings", label: "Task Types", priority: 3

  permit_params :name, :department_id, :sla_minutes

  filter :name
  filter :department

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
    end
  end

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)
    f.inputs "Task Type" do
      f.input :department
      f.input :name
      f.input :sla_minutes, hint: "Minutes before a task of this type is flagged over SLA."
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

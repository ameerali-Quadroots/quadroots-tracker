ActiveAdmin.register ApprovalFlow do
  menu parent: "Settings", label: "Approval Flows", priority: 3

  permit_params :name, :subject_type, :request_type, :active,
                approval_steps_attributes: [:id, :role_id, :name, :position, :optional, :_destroy]

  filter :name
  filter :subject_type, as: :select, collection: ApprovalFlow::SUBJECT_TYPES
  filter :active

  index do
    selectable_column
    column :name
    column("Applies to") do |flow|
      flow.request_type.presence || "All #{flow.subject_type.underscore.humanize.downcase.pluralize}"
    end
    column("Chain") { |flow| flow.summary }
    column :active
    actions
  end

  show do
    attributes_table do
      row :name
      row :subject_type
      row("Applies to") { |f| f.request_type.presence || "Everything not matched by another flow" }
      row :active
    end

    panel "Steps" do
      table_for approval_flow.approval_steps do
        column("#") { |s| s.position + 1 }
        column("Role") { |s| s.role&.name }
        column("Label") { |s| s.name }
        column("Optional") { |s| s.optional? ? "Skipped if nobody holds the role" : "Required" }
      end
    end
  end

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "Flow" do
      f.input :name
      f.input :subject_type, as: :select, collection: ApprovalFlow::SUBJECT_TYPES, include_blank: false
      f.input :request_type, as: :select,
              collection: EditRequest.distinct.pluck(:request_type).compact.sort,
              include_blank: "All (catch-all for this subject)",
              hint: "Leave blank to cover every request type without its own flow."
      f.input :active
    end

    f.inputs "Steps" do
      para "Requests move through these in order. Each step is filled by the nearest " \
           "person above the requester in the organogram holding that role.",
           style: "color:#64748B; font-size:0.85rem; margin-bottom:10px;"

      f.has_many :approval_steps, sortable: :position, sortable_start: 0,
                 allow_destroy: true, new_record: "Add step" do |s|
        s.input :role, as: :select,
                collection: [
                  ["Tracker app roles", Role.active.for_scope(:employee).ordered.pluck(:name, :id)],
                  ["Admin panel roles (settled from the admin panel only)",
                   Role.active.for_scope(:admin).ordered.pluck(:name, :id)]
                ],
                include_blank: false
        s.input :name, label: "Label", hint: "Defaults to the role name."
        s.input :optional, label: "Skip if nobody holds this role"
      end
    end

    f.actions
  end
end

ActiveAdmin.register AppSetting do
  menu parent: "Settings", label: "Request Limits", priority: 4

  actions :index, :edit, :update

  permit_params :edit_request_monthly_limit

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)
    f.inputs "Edit request limits" do
      f.input :edit_request_monthly_limit, label: "Monthly limit per employee",
              hint: "Maximum number of time-clock edit requests an employee may submit in a calendar month."
    end
    f.actions
  end

  controller do
    # This is a singleton settings row: index and edit both just work the one record.
    def index
      redirect_to edit_admin_app_setting_path(AppSetting.instance)
    end

    def update
      super do |success, failure|
        success.html { redirect_to edit_admin_app_setting_path(resource), notice: "Request limits updated." }
        failure.html { render :edit }
      end
    end
  end
end

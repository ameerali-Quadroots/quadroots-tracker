# app/admin/employees.rb
ActiveAdmin.register User, as: "Employee" do
  # Display "Employees" in the sidebar menu
  menu label: "Employees"

  # Allow these params to be editable in ActiveAdmin forms
  permit_params :name, :email, :phone_number, :address,
                :password, :password_confirmation,
                :role, :department, :shift_time

  # Filters for search
  filter :name
  filter :email
  filter :department
  filter :role
  filter :time_clocks_clock_in
  filter :time_clocks_clock_out
  filter :time_clocks_created_at

  # INDEX page
  index do
    selectable_column

    column :name
    column :email
    column :department
    column :role

    column "Medical Leaves (Approved)" do |employee|
      employee.medical_leaves_count
    end

    column "Casual Leaves (Approved)" do |employee|
      employee.casual_leaves_count
    end

    column "Half Days (Approved)" do |employee|
      employee.half_days_count
    end

    column "Remaining Medical Leaves" do |employee|
      employee.remaining_medical_leaves
    end

    column "Remaining Casual Leaves" do |employee|
      employee.remaining_casual_leaves
    end

    column "Absent Days" do |employee|
      employee.absent_days_count
    end
    actions defaults: true do |employee|
  # View timesheets
  links = []
  links << link_to("View Timesheets", admin_employee_time_clocks_path(employee), class: "member_link")
  links << link_to("View Timesheets Calendar", calendar_timesheets_admin_employee_path(employee), class: "member_link")

  # Mark as unemployed (only if currently employed)
  if employee.employeed?
    links << link_to("Mark as Unemployed", mark_as_unemployed_admin_employee_path(employee),
                     method: :put,
                     data: { confirm: "Are you sure you want to mark this employee as unemployed?" },
                     class: "member_link")
  end

  safe_join(links, " ")
end


  end

  # FORM for create/edit
  form do |f|
    f.inputs "Employee Details" do
      f.input :name
      f.input :email
      f.input :phone_number
      f.input :address

      f.input :department, as: :select,
        collection: ['SEO', 'SALES', 'ADS', 'PMO', 'WEB', 'SMM', 'CST', 'HR', 'IT','CONTENT','QA','ACCOUNTS', 'Executive Board', "HOD'S"],
        prompt: "Select Department"

      f.input :role, as: :select,
        collection: User.roles.keys,
        input_html: { class: "dropdown", style: "width:50%" }

      f.input :shift_time
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end

  # Add action button on show page
  action_item :view_time_clocks, only: :show do
    link_to 'View Time Clocks', admin_employee_time_clocks_path(resource)
    link_to "View Timesheets Calendar", calendar_timesheets_admin_employee_path(resource)

  end


  show do
    attributes_table do
      row :name
      row :email
      row :phone_number
      row :address
      row :role
      row :department
      row "Shift Time" do |employee|
        # Display in 12-hour format, e.g. "06:00 PM"
        employee.shift_time.strftime("%I:%M %p") if employee.shift_time.present?
      end
    end

    # Optional: show action buttons for related data
    panel "Timesheets" do
      link_to "View Employee Timesheets", admin_employee_time_clocks_path(resource)
    end
  end

  member_action :calendar_timesheets, method: :get do
  @employee = resource
  @time_clocks = @employee.time_clocks.order(:clock_in)

  render "admin/employees/calendar_timesheets"
end

member_action :mark_as_unemployed, method: :put do
  user = User.find(params[:id])

  if user.update(employeed: false)
    redirect_back fallback_location: admin_employee_path,
                  notice: "#{user.name || 'User'} has been marked as unemployed."
  else
    redirect_back fallback_location: admin_employee_path,
                  alert: "Failed to update employment status."
  end
end



end

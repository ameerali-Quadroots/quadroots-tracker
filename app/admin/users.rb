# app/admin/employees.rb
ActiveAdmin.register User, as: "Employee" do
  # Display "Employees" in the sidebar menu
  menu label: "Employees"

  # Allow these params to be editable in ActiveAdmin forms
  permit_params :name, :email, :phone_number, :address,
                :password, :password_confirmation,
                :role, :department, :shift_time, :image

  # Filters for search
  filter :name
  filter :email
  filter :department
  filter :role
  filter :time_clocks_clock_in
  filter :time_clocks_clock_out
  filter :time_clocks_created_at
  filter :employeed, as: :boolean, label: "Employment Status"

  scope :all, default: true
  scope("Employed", :employed) { |users| users.where(employeed: true) }
  scope("Unemployed", :unemployed) { |users| users.where(employeed: [false, nil]) }

  # INDEX page
  index do
    selectable_column

    column :name
    column :email
    column :department
    column :role

    column "Medical Used" do |employee|
      employee.medical_leaves_count
    end

    column "Casual Used" do |employee|
      employee.casual_leaves_count
    end

    column "Half Days" do |employee|
      employee.half_days_count
    end

    column "Medical Left" do |employee|
      employee.remaining_medical_leaves
    end

    column "Casual Left" do |employee|
      employee.remaining_casual_leaves
    end

    column "Absent" do |employee|
      employee.absent_days_count
    end
    actions defaults: true do |employee|
  # View timesheets
  links = []
  links << link_to("Timesheets", admin_employee_time_clocks_path(employee), class: "member_link", title: "View Timesheets")
  links << link_to("Calendar", calendar_timesheets_admin_employee_path(employee), class: "member_link", title: "View Timesheets Calendar")

  # Mark as unemployed (only if currently employed)
  if employee.employeed?
    links << link_to("Unemploy", mark_as_unemployed_admin_employee_path(employee),
                     method: :put,
                     data: { confirm: "Are you sure you want to mark this employee as unemployed?" },
                     class: "member_link", title: "Mark as Unemployed")
  else
    links << link_to("Re-employ", mark_as_employed_admin_employee_path(employee),
                     method: :put,
                     data: { confirm: "Are you sure you want to mark this employee as employed?" },
                     class: "member_link", title: "Mark as Employed")
  end

  safe_join(links, " ")
end


  end

  # FORM for create/edit
  form do |f|
    f.inputs "Employee Details" do
      f.input :image, as: :file,
        hint: f.object.image.attached? ? image_tag(f.object.image, style: "max-width:120px;max-height:120px;border-radius:8px;margin-top:6px;") : "Upload a profile photo (JPG/PNG)"
      f.input :name
      f.input :email
      f.input :phone_number
      f.input :address

      f.input :department, as: :select,
        collection: ['SEO', 'SALES', 'ADS', 'PMO', 'WEB', 'SMM', 'CST', 'HR', 'IT','CONTENT','QA','ACCOUNTS', 'Executive Board', "HOD'S", "HAB BDR"],
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
    render partial: "admin/employees/show", locals: { employee: resource }
  end

  member_action :calendar_timesheets, method: :get do
  @employee = resource
  @time_clocks = @employee.time_clocks.includes(:breaks).order(:clock_in)

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

member_action :mark_as_employed, method: :put do
  user = User.find(params[:id])

  if user.update(employeed: true)
    redirect_back fallback_location: admin_employee_path,
                  notice: "#{user.name || 'User'} has been marked as employed."
  else
    redirect_back fallback_location: admin_employee_path,
                  alert: "Failed to update employment status."
  end
end


end

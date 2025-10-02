ActiveAdmin.register User do

    permit_params :name, :email, :phone_number, :address, :password, :password_confirmation, :role, :department, :shift_time
  
    filter :name
    filter :email
    filter :department
  
    # Correctly filter on the TimeClock association
    filter :time_clocks_clock_in
    filter :time_clocks_clock_out
    filter :time_clocks_created_at
    filter :department
  

    index do
      selectable_column
      
      column :name
      column :email
      column :created_at
      column :updated_at
      
      actions defaults: true do |user|
        link_to "View Timesheets", admin_user_time_clocks_path(user), class: "member_link"
      end
    end


    form do |f|
        f.inputs "User Details" do
          f.input :name
          f.input :email
          f.input :phone_number
          f.input :address
          f.input :department, as: :select, collection: ['SEO', 'SALES', 'ADS', 'PMO', 'WEB', 'SMM', 'CST', 'HR', 'IT','CONTENT','QA','ACCOUNTS', 'CORE'], prompt: "Select Department"
          f.input :role, as: :select, collection: User.roles.keys,
          input_html: { class: "dropdown", style: "width:50%"}
          f.input :shift_time
          f.input :password
          f.input :password_confirmation
        end
        f.actions
      end


      
action_item :view_time_clocks, only: :show do
  link_to 'View Time Clocks', admin_user_time_clocks_path(resource)
end

  end
  
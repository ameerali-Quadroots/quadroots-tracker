ActiveAdmin.register User do
    permit_params :name, :email, :phone_number, :address, :password, :password_confirmation, :role
  
    filter :name
    filter :email
  
    # Correctly filter on the TimeClock association
    filter :time_clocks_clock_in
    filter :time_clocks_clock_out
    filter :time_clocks_created_at
  

    index do
      selectable_column
      id_column
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
          f.input :role, as: :select, collection: User.roles.keys,
          input_html: { class: "dropdown"}
          f.input :password
          f.input :password_confirmation
        end
        f.actions
      end


      

  end
  
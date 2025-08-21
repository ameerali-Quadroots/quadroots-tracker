ActiveAdmin.register User do
    permit_params :name, :email, :phone_number, :address, :password, :password_confirmation, :role
  
    filter :name
    filter :email
  
    # Correctly filter on the TimeClock association
    filter :time_clocks_clock_in_gteq, label: 'Clock In After'  # Use the association + attribute name
    filter :time_clocks_clock_out_lteq, label: 'Clock Out Before'
    filter :time_clocks_user_id_eq, label: 'User ID for TimeClock'  # Correct filter for user_id on TimeClock
    filter :time_clocks_hours_worked_eq, label: 'Hours Worked'  # Filter based on hours worked in time_clocks
  

    index do
      selectable_column
      id_column
      column :name
      column :email
      column :role
      actions
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
  
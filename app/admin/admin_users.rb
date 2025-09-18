ActiveAdmin.register AdminUser do

  controller do
    before_action :authorize_admin_user!

    def authorize_admin_user!
      authorize! :manage, AdminUser
    end
  end
  
  permit_params :email, :password, :password_confirmation, :role

  index do
    selectable_column
    id_column
    column :email
    actions
  end

  filter :email


  form do |f|
    f.inputs do
      f.input :email
    f.input :role, as: :select, collection: AdminUser.roles.keys,
          input_html: { class: "dropdown", style: "width:50%"}  
     f.input :password
      f.input :password_confirmation

    end
    f.actions
  end

end

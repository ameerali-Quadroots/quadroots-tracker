class AddDepartmentToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :department, :string
  end
end

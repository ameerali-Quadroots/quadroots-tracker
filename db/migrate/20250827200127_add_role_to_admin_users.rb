class AddRoleToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :role, :string, default: "admin"
    add_index :admin_users, :role
  end
end

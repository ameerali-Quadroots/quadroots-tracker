class AddRoleAndDepartmentRefsToUsers < ActiveRecord::Migration[7.1]
  def change
    # Added alongside the existing `role` / `department` string columns, which
    # stay in place and keep being written, so every current
    # `user.role == "Manager"` check keeps working while call sites migrate.
    add_reference :users, :role, foreign_key: true, null: true
    add_reference :users, :department, foreign_key: true, null: true
    add_reference :users, :reports_to, foreign_key: { to_table: :users }, null: true

    add_reference :admin_users, :role, foreign_key: true, null: true
    add_reference :admin_users, :department, foreign_key: true, null: true
  end
end

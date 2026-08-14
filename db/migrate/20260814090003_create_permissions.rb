class CreatePermissions < ActiveRecord::Migration[7.1]
  def change
    create_table :permissions do |t|
      # "resource" => a CanCan rule (subject + action) for the admin panel.
      # "page"     => a named screen in the employee-facing app.
      t.string  :kind, null: false
      t.string  :subject
      t.string  :action
      t.string  :key, null: false
      t.string  :label, null: false
      t.string  :group
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :permissions, :key, unique: true
    add_index :permissions, [:kind, :subject]

    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: true
      t.references :permission, null: false, foreign_key: true
      t.timestamps
    end

    add_index :role_permissions, [:role_id, :permission_id], unique: true
  end
end

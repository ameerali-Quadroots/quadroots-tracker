class CreateRoles < ActiveRecord::Migration[7.1]
  def change
    create_table :roles do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      # Which login this role applies to: "employee", "admin" or "both".
      t.string  :scope, default: "employee", null: false
      # Seniority, used to order the organogram. Lower number = more senior.
      t.integer :rank, default: 100, null: false
      t.text    :description
      # System roles cannot be deleted or have their permissions edited away
      # (guards against locking everyone out of the admin panel).
      t.boolean :system, default: false, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :roles, :name, unique: true
    add_index :roles, :slug, unique: true
    add_index :roles, :scope
  end
end

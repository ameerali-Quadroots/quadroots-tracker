class CreateUserManagers < ActiveRecord::Migration[7.1]
  def up
    create_table :user_managers do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.references :manager, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :user_managers, [:user_id, :manager_id], unique: true

    # Backfill from the existing single `reports_to_id` so nobody's
    # reporting line disappears when this ships.
    execute <<~SQL
      INSERT INTO user_managers (user_id, manager_id, created_at, updated_at)
      SELECT id, reports_to_id, NOW(), NOW() FROM users WHERE reports_to_id IS NOT NULL
    SQL
  end

  def down
    drop_table :user_managers
  end
end

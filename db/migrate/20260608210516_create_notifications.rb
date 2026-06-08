class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :message, null: false
      t.string :url, default: '/'
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [:user_id, :read_at]
  end
end

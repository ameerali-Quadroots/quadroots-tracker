class AddEmployeedToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :employeed, :boolean, default: true
  end
end

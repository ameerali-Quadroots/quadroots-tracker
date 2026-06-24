class AddSudoNameToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :sudo_name, :string
  end
end

class ChangeEmployeedDefaultToTrueInUsers < ActiveRecord::Migration[7.1]
  def change
    change_column_default :users, :employeed, from: nil, to: true
    change_column_default :users, :employeed, from: false, to: true

    reversible do |dir|
      dir.up do
        User.where(employeed: nil).update_all(employeed: true)
      end
    end
  end
end

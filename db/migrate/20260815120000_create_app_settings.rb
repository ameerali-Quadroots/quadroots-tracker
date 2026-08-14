class CreateAppSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :app_settings do |t|
      # Max edit requests an employee may submit within a single calendar month.
      t.integer :edit_request_monthly_limit, default: 3, null: false
      t.timestamps
    end
  end
end

class CreateEditRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :edit_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :time_clock, null: false, foreign_key: true
      t.datetime :requested_clock_in
      t.text :reason
      t.string :status
      t.text :manager_note
      t.datetime :resolved_at
      t.string :department
      
      t.boolean :approved_by_manager
      t.boolean :approved_by_admin
      t.string :request_type

      t.timestamps
    end
  end
end

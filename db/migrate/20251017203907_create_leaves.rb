class CreateLeaves < ActiveRecord::Migration[7.1]
  def change
    create_table :leaves do |t|
      t.references :user, null: false, foreign_key: true
      t.string :leave_type
      t.date :start_date
      t.date :end_date
      t.text :reason
      t.string :status
      t.boolean :approved_by_manager, default: false

      t.timestamps
    end
  end
end

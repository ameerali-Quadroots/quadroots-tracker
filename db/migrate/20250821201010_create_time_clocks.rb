class CreateTimeClocks < ActiveRecord::Migration[7.1]
  def change
    create_table :time_clocks do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :clock_in
      t.datetime :clock_out

      t.timestamps
    end
  end
end

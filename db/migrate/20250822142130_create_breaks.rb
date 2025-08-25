class CreateBreaks < ActiveRecord::Migration[7.1]
  def change
    create_table :breaks do |t|
      t.references :time_clock, null: false, foreign_key: true
      t.datetime :break_in
      t.datetime :break_out

      t.timestamps
    end
  end
end

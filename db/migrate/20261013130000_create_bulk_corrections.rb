# One row per bulk late-mark correction run from the admin panel (e.g. the
# server was down, so nobody who clocked in late that day should be counted
# late). Kept so a correction can be explained later and undone.
class CreateBulkCorrections < ActiveRecord::Migration[7.1]
  def change
    create_table :bulk_corrections do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.date :shift_date, null: false
      t.string :reason, null: false
      t.string :scope_label, null: false
      t.jsonb :time_clock_ids, null: false, default: []
      t.datetime :undone_at
      t.references :undone_by, foreign_key: { to_table: :admin_users }
      t.timestamps
    end
  end
end

# Marks a time clock whose clock-in was corrected by a "Clock tower not working"
# request that went through the approval chain (manager, then admin), so the
# timesheets can show "On Time · Corrected" instead of a plain "On Time".
# Existing corrections are filled in from the approved requests.
class AddClockInCorrectedAtToTimeClocks < ActiveRecord::Migration[7.1]
  def up
    add_column :time_clocks, :clock_in_corrected_at, :datetime

    execute <<~SQL
      UPDATE time_clocks
      SET clock_in_corrected_at = corrected.at
      FROM (
        SELECT time_clock_id, MAX(COALESCE(resolved_at, updated_at)) AS at
        FROM edit_requests
        WHERE request_type = 'Clock tower not working'
          AND status = 'approved'
          AND approved_by_manager = TRUE
          AND approved_by_admin = TRUE
        GROUP BY time_clock_id
      ) corrected
      WHERE time_clocks.id = corrected.time_clock_id
    SQL
  end

  def down
    remove_column :time_clocks, :clock_in_corrected_at
  end
end

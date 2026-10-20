namespace :time_clocks do
  desc "Re-decide late/on_time for clock-ins corrected by 'Clock tower not working' requests approved by manager then admin (preview by default; DRY_RUN=false to apply)"
  task recompute_status: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    # Approving these used to force "on_time" whatever the requested time was.
    # Only requests that went through the chain - manager first, then admin.
    ids = EditRequest.approved
                     .where(request_type: "Clock tower not working", approved_by_manager: true, approved_by_admin: true)
                     .distinct.pluck(:time_clock_id)
    # Shifts a bulk correction deliberately forgave stay on time.
    forgiven = BulkCorrection.where(undone_at: nil).pluck(:time_clock_ids).flatten.map(&:to_i)

    changed = 0

    TimeClock.where(id: ids - forgiven).includes(:employee).find_each do |tc|
      status = tc.computed_status
      next if status.nil? || status == tc.status

      puts "time_clock #{tc.id} (user #{tc.user_id}) #{tc.clock_in}: #{tc.status} -> #{status}"
      tc.update_columns(status: status, updated_at: Time.current) unless dry_run
      changed += 1
    end

    puts dry_run ? "DRY RUN - #{changed} shifts would change" : "Updated #{changed} shifts"
  end
end

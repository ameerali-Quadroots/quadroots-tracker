namespace :breaks do
  desc "One-off repair: close breaks left open on shifts that are already clocked out, and recompute their durations"
  task repair_dangling: :environment do
    dry_run = ENV["DRY_RUN"] == "true"

    scope = TimeClock.where.not(clock_out: nil)
                     .where(id: Break.where(break_out: nil).select(:time_clock_id))
                     .includes(:breaks)

    fixed = 0

    scope.find_each do |tc|
      tc.open_breaks.each do |b|
        closes_at = [tc.clock_out, b.break_in].max
        puts "time_clock #{tc.id} (user #{tc.user_id}): break #{b.id} #{b.break_type} " \
             "#{b.break_in} -> #{closes_at}"
        b.update!(break_out: closes_at) unless dry_run
      end

      unless dry_run
        break_seconds = tc.total_break_seconds
        tc.update!(
          total_duration: [(tc.clock_out - tc.clock_in).to_i - break_seconds, 0].max,
          break_duration: break_seconds
        )
      end

      fixed += 1
    end

    puts dry_run ? "DRY RUN - #{fixed} shifts would be repaired" : "Repaired #{fixed} shifts"
  end
end

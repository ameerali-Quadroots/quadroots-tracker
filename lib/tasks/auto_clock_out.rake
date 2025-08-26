# lib/tasks/auto_clock_out.rake
namespace :time_clocks do
  desc "Auto clock out users who forgot to clock out"
  task auto_clock_out: :environment do
    now = Time.zone.now
    puts "Running auto clock out at #{now}"

    TimeClock.where(clock_out: nil).find_each do |tc|
      total_worked_seconds = now - tc.clock_in

      # Subtract breaks if present
      break_seconds = 0
      if tc.respond_to?(:breaks) && tc.breaks.any?
        break_seconds = tc.breaks.sum do |br|
          (br.break_out || now) - br.break_in
        end
        total_worked_seconds -= break_seconds
      end

      tc.update(clock_out: now, total_duration: total_worked_seconds.to_i, break_duration: break_seconds)
      puts "Clocked out user #{tc.user_id} at #{now}"
    end
  end
end

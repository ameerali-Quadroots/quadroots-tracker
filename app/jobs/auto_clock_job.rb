# Clocks out everyone who forgot to, at the end of their own shift: 5 AM for an
# 8 PM start, 5:30 AM for 8:30 PM. Runs every 30 minutes (config/schedule.rb)
# and only closes shifts whose end has passed, at that end time - so a late or
# missed run never credits extra hours.
class AutoClockJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.zone.now
    Rails.logger.info "Running auto clock out at #{now}"

    TimeClock.where(clock_out: nil).where.not(clock_in: nil).includes(:breaks, :employee).find_each do |tc|
      ends_at = tc.scheduled_clock_out
      next if ends_at.nil? || ends_at > now

      at = [ends_at, tc.clock_in].max
      forgotten = tc.open_breaks.size
      tc.close_out!(at: at)

      Rails.logger.info "Clocked out user #{tc.user_id} at #{at}, set current_state to 'off', " \
                        "total_duration: #{tc.total_duration}, break_duration: #{tc.break_duration}, " \
                        "auto-ended breaks: #{forgotten}"
    rescue StandardError => e
      # One bad record must not stop the rest of the sweep.
      Rails.logger.error "AutoClockJob failed for time_clock #{tc.id} (user #{tc.user_id}): #{e.message}"
    end
  end
end

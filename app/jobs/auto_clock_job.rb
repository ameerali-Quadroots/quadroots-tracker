class AutoClockJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.zone.now
    Rails.logger.info "Running auto clock out at #{now}"

    TimeClock.where(clock_out: nil).includes(:breaks).find_each do |tc|
      next if tc.clock_in.blank?

      forgotten = tc.open_breaks.size
      tc.close_out!(at: now)

      Rails.logger.info "Clocked out user #{tc.user_id} at #{now}, set current_state to 'off', " \
                        "total_duration: #{tc.total_duration}, break_duration: #{tc.break_duration}, " \
                        "auto-ended breaks: #{forgotten}"
    rescue StandardError => e
      # One bad record must not stop the rest of the sweep.
      Rails.logger.error "AutoClockJob failed for time_clock #{tc.id} (user #{tc.user_id}): #{e.message}"
    end
  end
end

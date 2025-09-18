class AutoClockJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.zone.now
    Rails.logger.info "Running auto clock out at #{now}"

    TimeClock.where(clock_out: nil).find_each do |tc|
      total_worked_seconds = now - tc.clock_in

      # Calculate break time, excluding 'meeting' breaks
      break_seconds = 0
      if tc.respond_to?(:breaks) && tc.breaks.any?
        non_meeting_breaks = tc.breaks.where.not(break_type: "Meeting")

        break_seconds = non_meeting_breaks.sum do |br|
          (br.break_out || now) - br.break_in
        end

        total_worked_seconds -= break_seconds
      end

      tc.update(
        clock_out: now,
        total_duration: [total_worked_seconds.to_i, 0].max,
        break_duration: break_seconds.to_i,
        current_state: "off"
      )

      Rails.logger.info "Clocked out user #{tc.user_id} at #{now}, set current_state to 'off', total_duration: #{total_worked_seconds.to_i}, break_duration: #{break_seconds.to_i}"
    end
  end
end

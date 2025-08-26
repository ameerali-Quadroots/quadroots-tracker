class TimeClocksController < ApplicationController
  before_action :authenticate_user!

  # ------------------------
  # CLOCK IN
  # ------------------------
  def clock_in
    now = Time.current

    # Determine shift start and end (6 PM → 3 AM next day)
    shift_start_today = now.change(hour: 18, min: 0, sec: 0)
    shift_end_today   = shift_start_today + 9.hours

    shift_start_yesterday = shift_start_today - 1.day
    shift_end_yesterday   = shift_start_yesterday + 9.hours

    # Find which shift 'now' belongs to
    if (shift_start_yesterday..shift_end_yesterday).cover?(now)
      shift_start = shift_start_yesterday
      shift_end   = shift_end_yesterday
    elsif (shift_start_today..shift_end_today).cover?(now)
      shift_start = shift_start_today
      shift_end   = shift_end_today
    else
      redirect_to root_path, alert: "You cannot clock in before 6:00 PM."
      return
    end

    # Prevent duplicate clock-in
    if current_user.time_clocks.where(clock_in: shift_start..shift_end).exists?
      redirect_to root_path, alert: "You have already clocked in for this shift."
      return
    end

    # Determine late or on_time
    late_time = shift_start + 10.minutes
    status = now > late_time ? "late" : "on_time"

    # Create the clock record
    current_user.time_clocks.create!(
      clock_in: now,
      status: status,
      current_state: "working"
    )

    redirect_to root_path, notice: "Clocked in successfully (#{status})."
  end

  # ------------------------
  # CLOCK OUT
  # ------------------------
  def clock_out
    time_clock = current_user.time_clocks.where(clock_out: nil).last

    if time_clock.present?
      now = Time.current
      total_worked_seconds = now - time_clock.clock_in

      # Subtract breaks
      break_seconds = 0
      if time_clock.respond_to?(:breaks) && time_clock.breaks.any?
        break_seconds = time_clock.breaks.sum do |br|
          (br.break_out || now) - br.break_in
        end
        total_worked_seconds -= break_seconds
      end

      # Update the clock record
      time_clock.update!(
        clock_out: now,
        total_duration: total_worked_seconds.to_i,
        break_duration: break_seconds.to_i,
        current_state: "off"
      )
    end

    redirect_to root_path, notice: "Clocked out successfully."
  end
end

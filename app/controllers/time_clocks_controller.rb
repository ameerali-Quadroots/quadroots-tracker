class TimeClocksController < ApplicationController
    before_action :authenticate_user!
  
  def clock_in
  now = Time.current

  # Determine the shift start for today
  shift_start_today = now.change(hour: 18, min: 0, sec: 0) # 6 PM today
  shift_end_today   = shift_start_today + 9.hours          # 3 AM next day

  # Determine the shift start for yesterday (in case it's after midnight)
  shift_start_yesterday = (shift_start_today - 1.day)
  shift_end_yesterday   = shift_start_yesterday + 9.hours

  # Check which shift "now" belongs to
  if (shift_start_yesterday..shift_end_yesterday).cover?(now)
    shift_start = shift_start_yesterday
    shift_end = shift_end_yesterday
  elsif (shift_start_today..shift_end_today).cover?(now)
    shift_start = shift_start_today
    shift_end = shift_end_today
  else
    # Not within any allowed shift
    redirect_to root_path, alert: "You cannot clock in before 6:00 PM."
    return
  end

  # Check if user already clocked in during this shift
  existing_clock_in = current_user.time_clocks.where(clock_in: shift_start..shift_end).exists?
  if existing_clock_in
    redirect_to root_path, alert: "You have already clocked in for this shift."
    return
  end

  # Late if after 6:10 PM (applies to shift_start time)
  late_time = shift_start + 10.minutes
  status = now > late_time ? "late" : "on_time"

  current_user.time_clocks.create(clock_in: now, status: status)
  redirect_to root_path, notice: "Clocked in successfully (#{status})."
end
    
  
    def clock_out
      time_clock = current_user.time_clocks.last
      if time_clock.present? && time_clock.clock_out.blank?
        now = Time.current
        total_worked_seconds = now - time_clock.clock_in
    
        # Subtract breaks (if you have a breaks table)
        if time_clock.respond_to?(:breaks) && time_clock.breaks.any?
          break_seconds = time_clock.breaks.sum do |br|
            (br.break_out || now) - br.break_in
          end
          total_worked_seconds -= break_seconds
        end
    
        time_clock.update(clock_out: now, total_duration: total_worked_seconds.to_i, break_duration: break_seconds)
      end
      redirect_to root_path
    end

  end
  
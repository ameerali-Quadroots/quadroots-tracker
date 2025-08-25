class TimeClocksController < ApplicationController
    before_action :authenticate_user!
  
    def clock_in
      now = Time.current
    
      # Define today's shift boundaries
      shift_start = now.change(hour: 18, min: 0, sec: 0) # 6:00 PM today
      shift_end   = (shift_start + 9.hours).change(sec: 0) # 3:00 AM next day
    
      # If it's before 6:00 PM, deny
      if now < shift_start
        redirect_to root_path, alert: "You cannot clock in before 6:00 PM."
        return
      end
    
      # Check if user already clocked in during this shift
      existing_clock_in = current_user.time_clocks.where(clock_in: shift_start..shift_end).exists?
      if existing_clock_in
        redirect_to root_path, alert: "You have already clocked in for this shift."
        return
      end
    
      # Mark late if after 6:10 PM
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
  
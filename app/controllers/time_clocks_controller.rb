class TimeClocksController < ApplicationController
  before_action :authenticate_user!

  # ------------------------
  # CLOCK IN
  # ------------------------
  def clock_in
  now = Time.current

  # Use the user's custom shift_time or fallback to 6:00 PM if not set
  user_shift_time = current_user.shift_time || Time.parse("18:00").in_time_zone

  # Convert to full datetime today/yesterday based on shift_time
  shift_start_today = now.change(hour: user_shift_time.hour, min: user_shift_time.min, sec: 0)
  shift_end_today   = shift_start_today + 9.hours

  shift_start_yesterday = shift_start_today - 1.day
  shift_end_yesterday   = shift_start_yesterday + 9.hours

  # Allow clock-in 15 minutes before shift starts
  early_start_today     = shift_start_today - 15.minutes
  early_start_yesterday = shift_start_yesterday - 15.minutes

  if (early_start_yesterday..shift_end_yesterday).cover?(now)
    shift_start = shift_start_yesterday
    shift_end   = shift_end_yesterday
  elsif (early_start_today..shift_end_today).cover?(now)
    shift_start = shift_start_today
    shift_end   = shift_end_today
  else
    redirect_to root_path, alert: "You cannot clock in outside your shift window."
    return
  end

  # Prevent duplicate clock-in
  if current_user.time_clocks.where(clock_in: shift_start..shift_end).exists?
    redirect_to root_path, alert: "You have already clocked in for this shift."
    return
  end

  # Late threshold: 16 minutes after actual shift start
  late_time = shift_start + 16.minutes
  status = now > late_time ? "late" : "on_time"

  current_user.time_clocks.create!(
    clock_in: now,
    status: status,
    current_state: "working",
    ip_address: request.remote_ip
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

    # Subtract only non-meeting breaks
    break_seconds = 0
    if time_clock.respond_to?(:breaks) && time_clock.breaks.any?
      non_meeting_breaks = time_clock.breaks.where.not(break_type: "Meeting")
      break_seconds = non_meeting_breaks.sum do |br|
        (br.break_out || now) - br.break_in
      end

      total_worked_seconds -= break_seconds
    end

    # Update the time clock record
    time_clock.update!(
      clock_out: now,
      total_duration: [total_worked_seconds.to_i, 0].max,
      break_duration: break_seconds.to_i,
      current_state: "off"
    )
  end

    redirect_to root_path, notice: "Clocked out successfully."
  end


  def show
    @date = params[:date]

    begin
      date = Date.parse(@date)
    rescue ArgumentError
      return render plain: "Invalid date", status: 400
    end

    @time_clock = current_user.time_clocks.find_by(clock_in: date.beginning_of_day..date.end_of_day)

    if @time_clock.nil?
      return render plain: "No time clock record found for #{@date}", status: 404
    end

    # @time_clock.breaks assumed to exist and be associated
  end

end

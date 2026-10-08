class BreaksController < ApplicationController
  before_action :set_time_clock

  # Starts a break - unless one is already running. One open break per shift is
  # the rule; a second click, a double submit or a stale page must not open
  # another. The row lock makes two simultaneous requests take turns, so the
  # second one sees the break the first one created.
  def break_in
    break_type = params[:break_type].to_s
    unless Break::VALID_BREAK_TYPES.include?(break_type)
      return redirect_to(root_path, alert: "That break type is not available.")
    end

    started = false
    @time_clock.with_lock do
      next if @time_clock.clock_out.present? || @time_clock.breaks.where(break_out: nil).exists?

      @time_clock.breaks.create!(break_in: Time.current, break_type: break_type)
      @time_clock.update!(current_state: state_for(break_type))
      started = true
    end

    if started
      TaskBreakSync.pause_for_break(current_user)
      redirect_to root_path, notice: "Break started!"
    elsif @time_clock.clock_out.present?
      redirect_to root_path, alert: "This shift has already ended."
    else
      redirect_to root_path, alert: "You are already on a break. End it before starting another."
    end
  end

  # Ends the break. Every open break on the shift is closed, not only the one
  # in the URL: if a bad state ever leaves more than one open, "End Break" has
  # to mean "I am back at work", not "one of my breaks is over".
  def break_out
    @time_clock.breaks.find(params[:id])   # 404 for a break that is not on this shift

    now = Time.current
    @time_clock.with_lock do
      @time_clock.breaks.where(break_out: nil).find_each do |open_break|
        open_break.update!(break_out: [now, open_break.break_in].max)
      end
      @time_clock.update!(current_state: "working") # Always return to working
    end

    TaskBreakSync.resume_after_break(current_user)
    redirect_to root_path, notice: "Break ended!"
  end

  private

  def set_time_clock
    @time_clock = current_user.time_clocks.find(params[:time_clock_id])
  end

  def state_for(break_type)
    case break_type
    when "Meeting" then "Meeting"
    when "Downtime" then "Downtime"
    else "On break"
    end
  end
end

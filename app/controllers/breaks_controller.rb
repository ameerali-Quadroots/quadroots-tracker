class BreaksController < ApplicationController
  before_action :set_time_clock

  def break_in
    break_type = params[:break_type]
    @time_clock.breaks.create!(break_in: Time.current, break_type: break_type)

    # Set the appropriate state
   new_state = case break_type
      when "Meeting"
        "Meeting"
      when "Downtime"
        "Downtime"
      else
        "On break"
      end

    @time_clock.update!(current_state: new_state)

    redirect_to root_path, notice: "Break started!"
  end

  def break_out
    break_record = @time_clock.breaks.find(params[:id])
    break_record.update!(break_out: Time.current)

    @time_clock.update!(current_state: "working") # Always return to working
    redirect_to root_path, notice: "Break ended!"
  end

  private

  def set_time_clock
    @time_clock = current_user.time_clocks.find(params[:time_clock_id])
  end
end

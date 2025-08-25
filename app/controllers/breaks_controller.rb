class BreaksController < ApplicationController
  before_action :set_time_clock

  def break_in
    @time_clock.breaks.create!(break_in: Time.current)
    redirect_to root_path, notice: "Break started!"
  end

  def break_out
    break_record = @time_clock.breaks.find(params[:id])
    break_record.update!(break_out: Time.current)
    redirect_to root_path, notice: "Break ended!"
  end

  private

  def set_time_clock
    @time_clock = current_user.time_clocks.find(params[:time_clock_id])
  end
end

class TimeClocksController < ApplicationController
    before_action :authenticate_user!
  
    def clock_in
      @time_clock = current_user.time_clocks.create(clock_in: Time.now)
      redirect_to root_path, notice: "Clocked in successfully."
    end
  
    def clock_out
      @time_clock = current_user.time_clocks.last
      @time_clock.update(clock_out: Time.now)
      redirect_to root, notice: "Clocked out successfully."
    end
  end
  
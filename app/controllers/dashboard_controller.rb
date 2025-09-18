class DashboardController < ApplicationController
    before_action :authenticate_user!  # Add the '!' here for proper authentication
    include DashboardHelper  # Make sure the helper is included

    def index
# shift_start = Time.zone.now.change(hour: 18, min: 0) # Today at 6:00 PM
# shift_end   = shift_start + 9.hours   

      @time_clock = current_user.time_clocks.last

# @time_clock = current_user.time_clocks
#   .where(clock_in: shift_start..shift_end)
#   .first
      # @time_clock = current_user.time_clocks
      #          .where(clock_in: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day).first


      monday = Date.today.beginning_of_week(:monday)
      friday = monday + 4.days
      
      @time_clocks = current_user.time_clocks
        .where(clock_in: monday.beginning_of_day..friday.end_of_day)
        .order(clock_in: :desc)
        @time_clocks_current_month = current_user.time_clocks
  .where(clock_in: Time.current.beginning_of_month..Time.current.end_of_month)
  .order(clock_in: :desc)

    end
  end
  
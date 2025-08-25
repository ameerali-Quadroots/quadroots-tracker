class DashboardController < ApplicationController
    before_action :authenticate_user!  # Add the '!' here for proper authentication
    include DashboardHelper  # Make sure the helper is included

    def index
      # @time_clock = current_user.time_clocks.last


      @time_clock = current_user.time_clocks
               .where(clock_in: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day).first


      monday = Date.today.beginning_of_week(:monday)
      friday = monday + 4.days
      
      @time_clocks = current_user.time_clocks
        .where(user_id: 1)
        .where(clock_in: monday.beginning_of_day..friday.end_of_day)
        .order(clock_in: :desc)
    end
  end
  
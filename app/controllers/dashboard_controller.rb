class DashboardController < ApplicationController
    before_action :authenticate_user!  # Add the '!' here for proper authentication
    include DashboardHelper  # Make sure the helper is included

    def index
      @time_clock = current_user.time_clocks.last
    end
  end
  
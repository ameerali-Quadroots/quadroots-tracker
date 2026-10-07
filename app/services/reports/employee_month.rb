module Reports
  # One employee's month, for the "Your month" section of their home page:
  # attendance, lateness against the KPI limit, hours, edit requests used
  # against the monthly allowance, and leave.
  #
  # `today` caps the daily series for the current month (injectable for tests).
  class EmployeeMonth
    attr_reader :user, :month

    def initialize(user:, month:, today: Time.zone.today)
      @user = user
      @month = month.beginning_of_month
      @today = today
    end

    def current_month?
      month == @today.beginning_of_month
    end

    # ---- Attendance ----------------------------------------------------------

    def days_worked
      clocks.size
    end

    def lates
      late_clocks.size
    end

    def on_time
      days_worked - lates
    end

    # nil when there were no shifts, so the page can say "no data" rather than 0%.
    def on_time_rate
      return nil if days_worked.zero?

      (on_time * 100.0 / days_worked).round(1)
    end

    # Newest first: [{ date:, clock_in:, minutes: }]
    def late_days
      late_clocks.sort_by(&:clock_in).reverse.map do |tc|
        { date: tc.shift_date, clock_in: tc.clock_in, minutes: tc.late_minutes }
      end
    end

    # On-time shifts in a row, counting back from the most recent one.
    def on_time_streak
      clocks.sort_by(&:clock_in).reverse.take_while { |tc| tc.status != "late" }.size
    end

    # ---- Lateness against the KPI rule (same setting as the admin KPI page) ---

    def late_limit
      @late_limit ||= AppSetting.instance.late_kpi_monthly_limit
    end

    def lates_left
      [late_limit - lates, 0].max
    end

    def kpi_deducted?
      lates > late_limit
    end

    # ---- Hours ---------------------------------------------------------------

    def total_hours
      (completed_seconds.sum / 3600.0).round(1)
    end

    def average_hours
      return nil if completed_seconds.empty?

      (completed_seconds.sum / completed_seconds.size / 3600.0).round(1)
    end

    # Mean arrival time, or nil with no shifts. Averaged as an offset from each
    # shift's start rather than as a time of day: the shift runs overnight, and
    # averaging 6pm with half past midnight as clock times would give noon.
    def average_clock_in
      return nil if clocks.empty?

      offset = clocks.sum { |tc| tc.clock_in - tc.shift_start } / clocks.size
      clocks.first.shift_start + offset
    end

    # One row per day, to today for the current month and to month end
    # otherwise: [{ date:, hours:, status: }] (status nil on a day not worked).
    def daily
      last_day = current_month? ? [@today, month.end_of_month].min : month.end_of_month
      by_day = clocks.group_by(&:shift_date)
      (month..last_day).map do |date|
        day = by_day.fetch(date, [])
        seconds = day.sum { |tc| tc.total_duration.to_i }
        { date: date, hours: (seconds / 3600.0).round(1),
          status: (day.any? { |tc| tc.status == "late" } ? "late" : day.first&.status) }
      end
    end

    # ---- Edit requests against the monthly allowance --------------------------
    # Counted by the day they were submitted, as EditRequest's own limit does.

    def edit_requests
      @edit_requests ||= user.edit_requests.where(created_at: time_range).order(created_at: :desc).to_a
    end

    def edit_requests_used
      edit_requests.size
    end

    def edit_request_limit
      @edit_request_limit ||= AppSetting.instance.edit_request_monthly_limit
    end

    def edit_requests_left
      [edit_request_limit - edit_requests_used, 0].max
    end

    # ---- Leave ---------------------------------------------------------------

    # Requests starting in the month that were not rejected, e.g. { "casual" => 1 }.
    def leaves_by_type
      user.leaves.where(start_date: month..month.end_of_month).where.not(status: "rejected").group(:leave_type).count
    end

    private

    def time_range
      Time.zone.local(month.year, month.month, 1).all_month
    end

    # By the day each shift started (TimeClock.on_shift_dates), so a clock-in
    # after midnight counts on the right day and in the right month.
    def clocks
      @clocks ||= user.time_clocks.on_shift_dates(month..month.end_of_month)
    end

    def late_clocks
      clocks.select { |tc| tc.status == "late" }
    end

    def completed_seconds
      @completed_seconds ||= clocks.filter_map(&:total_duration).select(&:positive?)
    end
  end
end

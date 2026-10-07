ActiveAdmin.register_page "Analytics" do
  menu label: "Analytics", priority: 2

  controller do
    helper_method :analytics_report, :analytics_range, :analytics_department_options, :analytics_period

    private

    # Preset periods, in days. (Methods, not constants: a constant defined in
    # this block would land on Object.)
    def analytics_periods
      { "7" => 7, "30" => 30, "90" => 90 }
    end

    def analytics_max_days
      366
    end

    # The preset in use ("7" / "30" / "90"), or nil when a custom range is set.
    def analytics_period
      return nil if custom_range

      analytics_periods.key?(params[:period]) ? params[:period] : "30"
    end

    # ?from=YYYY-MM-DD&to=YYYY-MM-DD wins; otherwise the last N days ending today.
    def analytics_range
      @analytics_range ||= custom_range || begin
        today = Time.zone.today
        (today - (analytics_periods.fetch(analytics_period) - 1))..today
      end
    end

    def custom_range
      return @custom_range if defined?(@custom_range)

      from = Date.iso8601(params[:from].to_s)
      to   = Date.iso8601(params[:to].to_s)
      from, to = to, from if from > to
      to = from + (analytics_max_days - 1) if (to - from) >= analytics_max_days
      @custom_range = from..to
    rescue ArgumentError
      @custom_range = nil
    end

    # Departments this admin may pick from; same scoping as Time Clocks and KPI.
    def analytics_department_options
      @analytics_department_options ||=
        if current_admin_user.super_admin? || current_admin_user.qa_admin?
          User.employed.distinct.pluck(:department).compact_blank.sort
        else
          current_admin_user.viewable_department_names
        end
    end

    def analytics_report
      @analytics_report ||= begin
        departments =
          if analytics_department_options.include?(params[:department])
            [params[:department]]
          elsif current_admin_user.super_admin? || current_admin_user.qa_admin?
            nil
          else
            analytics_department_options
          end

        Reports::AttendanceAnalytics.new(range: analytics_range, departments: departments)
      end
    end
  end

  content title: "Analytics" do
    render partial: "admin/analytics/report",
           locals: { report: analytics_report, range: analytics_range, period: analytics_period,
                     department_options: analytics_department_options,
                     open_employees: authorized?(:read, User) }
  end
end

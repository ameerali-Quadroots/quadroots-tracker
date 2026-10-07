module Reports
  # Monthly late-arrival KPI: one row per employed user with their late
  # clock-ins for the month, flagged once they go over the allowed limit.
  #
  # Nothing is persisted - the flag is derived from time_clocks.status on every
  # read, so an approved edit request that fixes a clock-in clears it by itself.
  class LateKpi
    UNASSIGNED = "Unassigned".freeze

    Row = Struct.new(:user, :department, :late_count, :kpi_deducted, keyword_init: true)
    Summary = Struct.new(:department, :total_employees, :total_lates, :flagged_count, keyword_init: true)

    attr_reader :month, :limit

    # departments: nil means every department, otherwise an array of names.
    def initialize(month:, limit: AppSetting.instance.late_kpi_monthly_limit, departments: nil)
      @month = month.beginning_of_month
      @limit = limit
      @departments = departments
    end

    # Flagged employees first, then by department and name.
    def rows
      @rows ||= employees.map do |user|
        lates = late_counts[user.id].to_i
        Row.new(user: user, department: user.department.presence || UNASSIGNED,
                late_count: lates, kpi_deducted: lates > limit)
      end.sort_by { |row| [row.kpi_deducted ? 0 : 1, row.department, row.user.name.to_s] }
    end

    def flagged_rows
      rows.select(&:kpi_deducted)
    end

    def department_summary
      @department_summary ||= rows.group_by(&:department).sort.map do |department, dept_rows|
        Summary.new(department: department,
                    total_employees: dept_rows.size,
                    total_lates: dept_rows.sum(&:late_count),
                    flagged_count: dept_rows.count(&:kpi_deducted))
      end
    end

    private

    def employees
      scope = User.employed
      scope = scope.where(department: @departments) unless @departments.nil?
      scope.to_a
    end

    def late_counts
      @late_counts ||= TimeClock.where(status: "late", clock_in: range).group(:user_id).count
    end

    def range
      Time.zone.local(month.year, month.month, 1).all_month
    end
  end
end

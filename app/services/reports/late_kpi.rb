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

    # Sort keys the KPI page offers. Names compare case-insensitively and
    # ignore stray spaces (a few are stored with a leading or trailing one).
    ROW_SORTS = {
      "name" => ->(row) { row.user.name.to_s.strip.downcase },
      "department" => ->(row) { row.department.to_s.strip.downcase },
      "lates" => ->(row) { row.late_count }
    }.freeze
    SUMMARY_SORTS = {
      "department" => ->(row) { row.department.to_s.downcase },
      "employees" => ->(row) { row.total_employees },
      "lates" => ->(row) { row.total_lates },
      "flagged" => ->(row) { row.flagged_count }
    }.freeze

    # rows sorted by one of ROW_SORTS / SUMMARY_SORTS; an unknown key returns
    # them untouched (the default order). Ties always fall back to A-Z, in
    # either direction, so "most lates first" does not also reverse the names.
    def self.sort(rows, sorts, by, direction)
      key = sorts[by] or return rows
      label = ->(row) { (row.respond_to?(:user) ? row.user.name : row.department).to_s.strip.downcase }

      rows.sort do |a, b|
        order = direction == "desc" ? key.call(b) <=> key.call(a) : key.call(a) <=> key.call(b)
        order.zero? ? label.call(a) <=> label.call(b) : order
      end
    end

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
      end.sort_by { |row| [row.kpi_deducted ? 0 : 1, row.department.to_s.strip.downcase, row.user.name.to_s.strip.downcase] }
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

    # Counted by the day each shift started, so a late clock-in just after
    # midnight on the 1st belongs to the month that was ending.
    def late_counts
      @late_counts ||= TimeClock.where(status: "late")
                                .on_shift_dates(month..month.end_of_month)
                                .group_by(&:user_id).transform_values(&:size)
    end
  end
end

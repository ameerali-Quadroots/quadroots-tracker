module Reports
  # Attendance figures for a date range, behind the admin Analytics page:
  # headline numbers (with the previous period for comparison), a per-day
  # series, and breakdowns by department, employee, lateness and leave type.
  #
  # A clock-in belongs to the day its shift started (TimeClock#shift_date), and
  # "late" is whatever time_clocks.status recorded at clock-in.
  class AttendanceAnalytics
    UNASSIGNED = "Unassigned".freeze

    # label => upper bound in minutes (inclusive)
    BUCKETS = [
      ["1–5 min", 5],
      ["6–15 min", 15],
      ["16–30 min", 30],
      ["31–60 min", 60],
      ["Over 1 hour", Float::INFINITY]
    ].freeze

    attr_reader :range

    def self.bucket_for(minutes)
      BUCKETS.find { |_, upper| minutes <= upper }.first
    end

    # range: a Date range. departments: nil for everyone, otherwise department names.
    def initialize(range:, departments: nil)
      @range = range
      @departments = departments
    end

    def employee_count
      employees.size
    end

    def summary
      @summary ||= summarize(clocks)
    end

    # The same number of days, ending the day before this range starts.
    def previous_summary
      @previous_summary ||= begin
        days = (range.end - range.begin).to_i + 1
        summarize(load_clocks((range.begin - days)..(range.begin - 1)))
      end
    end

    # One row per day in the range, zero-filled, so a chart never skips a date.
    def daily
      @daily ||= begin
        by_day = clocks.group_by(&:shift_date)
        range.map do |date|
          day = by_day.fetch(date, [])
          lates = day.count { |tc| tc.status == "late" }
          { date: date, on_time: day.size - lates, late: lates, avg_hours: average_hours(day) }
        end
      end
    end

    # Highest late rate first.
    def by_department
      @by_department ||= begin
        by_user = clocks.group_by(&:user_id)
        employees.group_by { |user| user.department.presence || UNASSIGNED }.map do |department, users|
          dept_clocks = users.flat_map { |user| by_user.fetch(user.id, []) }
          lates = dept_clocks.count { |tc| tc.status == "late" }
          { department: department, employees: users.size, clock_ins: dept_clocks.size, lates: lates,
            late_rate: percent(lates, dept_clocks.size) || 0.0 }
        end.sort_by { |row| [-row[:late_rate], row[:department]] }
      end
    end

    # Employees with at least one late arrival, most late first.
    def top_late(limit = 8)
      names = employees.index_by(&:id)
      late_clocks.group_by(&:user_id).map do |user_id, user_clocks|
        user = names[user_id]
        { id: user.id, name: user.name, department: user.department.presence || UNASSIGNED, lates: user_clocks.size }
      end.sort_by { |row| [-row[:lates], row[:name].to_s] }.first(limit)
    end

    # How late the late arrivals were, in BUCKETS order.
    def lateness_buckets
      counts = late_clocks.each_with_object(Hash.new(0)) do |tc, acc|
        acc[self.class.bucket_for(tc.late_minutes)] += 1
      end
      BUCKETS.to_h { |label, _| [label, counts[label]] }
    end

    # Leaves starting in the range, by type. Rejected requests never happened.
    def leaves_by_type
      Leave.where(user_id: employees.map(&:id), start_date: range)
           .where.not(status: "rejected")
           .group(:leave_type).count
           .sort_by { |type, count| [-count, type.to_s] }.to_h
    end

    private

    def employees
      @employees ||= begin
        scope = User.employed
        scope = scope.where(department: @departments) unless @departments.nil?
        scope.to_a
      end
    end

    def clocks
      @clocks ||= load_clocks(range)
    end

    def late_clocks
      clocks.select { |tc| tc.status == "late" }
    end

    # By the day each shift started (TimeClock.on_shift_dates), so a clock-in
    # after midnight is counted on the right day.
    def load_clocks(dates)
      TimeClock.where(user_id: employees.map(&:id)).on_shift_dates(dates)
    end

    def summarize(records)
      lates = records.count { |tc| tc.status == "late" }
      { clock_ins: records.size, lates: lates, on_time: records.size - lates,
        on_time_rate: percent(records.size - lates, records.size),
        avg_hours: average_hours(records) }
    end

    # nil when there is nothing to divide by, so callers can show "no data"
    # instead of a 0% that looks like a real result.
    def percent(part, whole)
      return nil if whole.zero?

      (part * 100.0 / whole).round(1)
    end

    def average_hours(records)
      durations = records.filter_map(&:total_duration).select(&:positive?)
      return nil if durations.empty?

      (durations.sum / durations.size / 3600.0).round(1)
    end
  end
end

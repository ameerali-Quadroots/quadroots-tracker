# Lives under app/services rather than a dedicated app/queries directory on
# purpose. Rails fixes its autoload ROOT directories at boot by globbing app/*,
# and never adds a root that appears later — so a brand-new top-level app/
# directory raises NameError in every app-server process that started before it
# existed, until that process is fully restarted. app/services already exists,
# and new subdirectories inside an existing root resolve fine.
module Reports
  # Daily task-time and attendance-time per executive for one department.
  #
  # Built from exactly two grouped aggregates no matter how many executives or
  # days are in range. This is the known N+1 hazard in this codebase (the
  # TimeClock breaks lookups that ignore eager loads), so never iterate records
  # to sum here — a test asserts the query count.
  class ExecutiveHours
    EMPTY_DAY = { task_seconds: 0, attendance_seconds: 0, gap_seconds: 0 }.freeze

    def initialize(department:, range:)
      @department = department
      @range = range
    end

    def executives
      @executives ||= User.employed
                          .joins(:access_role)
                          .where(department_id: @department&.id, roles: { name: "Executive" })
                          .order(:name)
    end

    def dates
      @dates ||= (@range.begin.to_date..@range.end.to_date).to_a
    end

    def matrix
      @matrix ||= build_matrix
    end

    def for(user_id, date)
      matrix.dig(user_id, date) || EMPTY_DAY
    end

    # Sums several days into one cell. The month view shows weeks-of-month
    # columns rather than thirty day columns, and reuses the already-built
    # matrix instead of re-querying.
    def bucket(user_id, dates)
      dates.reduce(EMPTY_DAY.dup) do |acc, date|
        cell = self.for(user_id, date)
        { task_seconds: acc[:task_seconds] + cell[:task_seconds],
          attendance_seconds: acc[:attendance_seconds] + cell[:attendance_seconds],
          gap_seconds: acc[:gap_seconds] + cell[:gap_seconds] }
      end
    end

    def columns(period)
      if period == "month"
        dates.group_by(&:beginning_of_week)
             .map { |week_start, days| ["w/c #{week_start.strftime('%d %b')}", days] }
      else
        dates.map { |date| [date.strftime("%d %b"), [date]] }
      end
    end

    def totals_for(user_id)
      days = matrix[user_id]&.values || []
      {
        task_seconds: days.sum { |d| d[:task_seconds] },
        attendance_seconds: days.sum { |d| d[:attendance_seconds] },
        gap_seconds: days.sum { |d| d[:gap_seconds] }
      }
    end

    private

    def build_matrix
      ids = executives.map(&:id)
      return {} if ids.empty?

      task = TaskWorkSession.where(user_id: ids, started_at: @range)
                            .group(:user_id, Arel.sql("DATE(started_at)"))
                            .sum(:duration_seconds)

      # total_duration is already net of breaks (TimeClock#calculate_total_duration).
      # Subtracting break_duration here would double-count them.
      attendance = TimeClock.where(user_id: ids, clock_in: @range)
                            .group(:user_id, Arel.sql("DATE(clock_in)"))
                            .sum(Arel.sql("COALESCE(total_duration, 0)"))

      result = Hash.new { |h, k| h[k] = {} }

      merge_into(result, task, :task_seconds)
      merge_into(result, attendance, :attendance_seconds)

      result.each_value do |days|
        days.each_value do |cell|
          cell[:gap_seconds] = [cell[:attendance_seconds] - cell[:task_seconds], 0].max
        end
      end
      result
    end

    def merge_into(result, aggregate, key)
      aggregate.each do |(user_id, date), seconds|
        date = date.to_date
        cell = (result[user_id][date] ||= { task_seconds: 0, attendance_seconds: 0, gap_seconds: 0 })
        cell[key] = seconds.to_i
      end
    end
  end
end

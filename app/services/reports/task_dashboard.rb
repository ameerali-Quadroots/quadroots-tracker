# Everything the manager dashboard puts on screen, as grouped aggregates.
#
# Lives under app/services for the same autoload reason as
# Reports::ExecutiveHours — see the note at the top of that file.
#
# The rule here matches ExecutiveHours: never iterate records to sum. The one
# deliberate exception is #over_sla_count, which cannot be pure SQL because an
# unfinished task's SLA breach is a function of the clock right now; that path
# loads only the handful of started-but-unfinished tasks rather than the whole
# department's history.
module Reports
  class TaskDashboard
    THROUGHPUT_DAYS = 14

    # Stack order follows the workflow, so the palette's adjacent pairs are the
    # ones that actually touch in a stacked bar.
    STATUS_ORDER = %w[pending in_progress paused completed].freeze

    def initialize(scope:, executives:, range:, previous_range: nil)
      @scope = scope
      @executives = executives
      @range = range
      @previous_range = previous_range
    end

    def counts_by_status
      @counts_by_status ||= @scope.group(:status).count
    end

    def total_tasks
      counts_by_status.values.sum
    end

    def count_for(status)
      counts_by_status[status].to_i
    end

    # Assigned work that someone is expected to act on — the manager's real
    # queue depth, which "total tasks" overstates once history piles up.
    def in_flight
      count_for("pending") + count_for("in_progress") + count_for("paused")
    end

    def over_sla_count
      @over_sla_count ||= completed_over_sla + active_over_sla
    end

    def completed_count
      count_for("completed")
    end

    def completed_over_sla
      @completed_over_sla ||= @scope.where(status: "completed", over_sla: true).count
    end

    # Share of finished work that landed inside its SLA. Nil rather than 100%
    # when nothing has been completed yet — an empty department has no record,
    # and showing "100% on time" would invent one.
    def on_time_rate
      return nil if completed_count.zero?

      ((completed_count - completed_over_sla) * 100.0 / completed_count).round
    end

    # [[executive_name, {status => count, ...}], ...] ordered by queue depth so
    # the most loaded person is the first bar the manager reads.
    def workload_by_executive
      @workload_by_executive ||= begin
        rows = @scope.group("users.name", :status).count
        by_name = rows.each_with_object({}) do |((name, status), count), acc|
          (acc[name] ||= {})[status] = count
        end
        by_name.sort_by { |_name, statuses| -STATUS_ORDER.sum { |s| statuses[s].to_i } }
      end
    end

    # Completed-per-day for the trailing fortnight, zero-filled so the line has
    # no gaps to interpolate across.
    def throughput
      @throughput ||= begin
        days = (THROUGHPUT_DAYS - 1).days.ago.to_date..Date.current
        counted = @scope.where(status: "completed", ended_at: days.first.beginning_of_day..days.last.end_of_day)
                        .group(Arel.sql("DATE(tasks.ended_at)")).count
        # DATE() comes back as a Date on PG, but be explicit — a string key
        # here would silently zero the whole series.
        normalized = counted.transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
        days.map { |day| [day, normalized[day].to_i] }
      end
    end

    def logged_seconds
      @logged_seconds ||= seconds_in(@range)
    end

    def previous_logged_seconds
      @previous_logged_seconds ||= @previous_range ? seconds_in(@previous_range) : 0
    end

    def logged_delta_seconds
      return nil if @previous_range.nil?

      logged_seconds - previous_logged_seconds
    end

    private

    def executive_ids
      @executive_ids ||= @executives.map(&:id)
    end

    def seconds_in(range)
      return 0 if executive_ids.empty?

      TaskWorkSession.where(user_id: executive_ids, started_at: range).sum(:duration_seconds)
    end

    # A task in progress or paused breaches its SLA the moment elapsed working
    # time passes the budget, so this figure has to be computed against the
    # current clock rather than read from the over_sla column.
    def active_over_sla
      @scope.where(status: %w[in_progress paused])
            .where.not(started_at: nil)
            .includes(:task_type)
            .count(&:over_sla?)
    end
  end
end

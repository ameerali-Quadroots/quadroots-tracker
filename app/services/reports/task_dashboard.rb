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

    # Team hours per day across the selected range, zero-filled so a quiet day
    # reads as a gap in the work rather than a gap in the chart.
    def hours_per_day
      @hours_per_day ||= begin
        days = @range.begin.to_date..@range.end.to_date
        logged = if executive_ids.empty?
                   {}
                 else
                   TaskWorkSession.where(user_id: executive_ids, started_at: @range)
                                  .group(Arel.sql("DATE(started_at)")).sum(:duration_seconds)
                                  .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
                 end
        days.map { |day| [day, logged[day].to_i] }
      end
    end

    # Hours by client for the range. Past the top few the tail is noise, so the
    # remainder is folded into a single "Other clients" row rather than drawn
    # as a queue of hairline bars — and internal work, which belongs to no
    # client, is named instead of silently dropped.
    CLIENT_ROWS = 6

    def hours_by_client
      @hours_by_client ||= begin
        rows = TaskWorkSession.joins(task: { sprint: { project: :client } })
                              .where(user_id: executive_ids, started_at: @range)
                              .group("clients.name").sum(:duration_seconds)

        internal = seconds_in(@range) - rows.values.sum
        rows["Internal work"] = internal if internal.positive?

        ranked = rows.sort_by { |_name, seconds| -seconds }
        return ranked if ranked.size <= CLIENT_ROWS

        head = ranked.first(CLIENT_ROWS - 1)
        tail = ranked.drop(CLIENT_ROWS - 1)
        head + [["#{tail.size} other clients", tail.sum(&:last)]]
      end
    end

    # ---- Breakdown tables ----------------------------------------------------
    # One row per executive, including anyone with nothing assigned, busiest
    # first. Counts are all-time (the department's whole backlog and history);
    # logged_seconds is for the selected range. over_sla is finished work that
    # went past its budget, and on_time_rate the share that did not - nil with
    # nothing finished, for the same reason as #on_time_rate above.
    def executive_breakdown
      @executive_breakdown ||= begin
        counts = @scope.group(:assigned_to_id, :status).count
        over   = @scope.where(status: "completed", over_sla: true).group(:assigned_to_id).count
        logged = if executive_ids.empty?
                   {}
                 else
                   TaskWorkSession.where(user_id: executive_ids, started_at: @range).group(:user_id).sum(:duration_seconds)
                 end

        @executives.map do |user|
          by_status = STATUS_ORDER.to_h { |status| [status.to_sym, counts[[user.id, status]].to_i] }
          completed = by_status[:completed]
          over_sla  = over[user.id].to_i
          by_status.merge(
            id: user.id, name: user.name, total: by_status.values.sum, over_sla: over_sla,
            on_time_rate: (completed.zero? ? nil : ((completed - over_sla) * 100.0 / completed).round),
            logged_seconds: logged[user.id].to_i
          )
        end.sort_by { |row| [-row[:total], row[:name].to_s.strip.downcase] }
      end
    end

    INTERNAL = "Internal work".freeze

    # One row per client that has tasks, most tasks first, plus "Internal work"
    # for tasks that belong to no client sprint. Counts are all-time,
    # logged_seconds is for the selected range.
    def client_breakdown
      @client_breakdown ||= begin
        by_client = @scope.left_joins(sprint: { project: :client })
        counts = by_client.group("clients.id", "clients.name", "tasks.status").count
        over   = by_client.where(status: "completed", over_sla: true).group("clients.id").count
        logged = if executive_ids.empty?
                   {}
                 else
                   TaskWorkSession.joins(task: { sprint: { project: :client } })
                                  .where(user_id: executive_ids, started_at: @range)
                                  .group("clients.id").sum(:duration_seconds)
                 end
        logged[nil] = [logged_seconds - logged.values.sum, 0].max   # time on work with no client

        counts.group_by { |(id, name, _status), _count| [id, name] }.map do |(id, name), entries|
          statuses  = entries.to_h { |(_id, _name, status), count| [status, count] }
          completed = statuses["completed"].to_i
          total     = statuses.values.sum
          { id: id, name: name || INTERNAL, total: total, open: total - completed, completed: completed,
            over_sla: over[id].to_i, logged_seconds: logged[id].to_i }
        end.sort_by { |row| [row[:id] ? 0 : 1, -row[:total], row[:name].to_s.strip.downcase] }
      end
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

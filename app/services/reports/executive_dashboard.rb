# The executive's own view of their work: what is running right now, what they
# have logged lately, and how their finished work landed against its SLA.
#
# Deliberately narrower than Reports::TaskDashboard — an executive gets no
# comparison against colleagues and no SLA figures for work still in progress,
# matching the existing rule that SLA is manager-side tracking.
module Reports
  class ExecutiveDashboard
    TREND_DAYS = 7

    def initialize(user:, tasks:)
      @user = user
      @tasks = tasks
    end

    def counts_by_status
      @counts_by_status ||= Task.for_executive(@user).group(:status).count
    end

    def count_for(status)
      counts_by_status[status].to_i
    end

    def open_count
      count_for("pending") + count_for("in_progress") + count_for("paused")
    end

    # The single task the timer is running on. Only one can be in progress at a
    # time, which is what makes it usable as the page's hero.
    def running_task
      return @running_task if defined?(@running_task)

      @running_task = @tasks.detect(&:in_progress?) ||
                      Task.for_executive(@user).in_progress.includes(:task_type, :assigned_by).first
    end

    def paused_tasks
      @paused_tasks ||= @tasks.select(&:paused?)
    end

    # What to offer when nothing is running: the most pressing unstarted task,
    # by due date then urgency.
    def next_up
      @next_up ||= @tasks.select(&:pending?)
                         .min_by { |t| [t.due_date || Date.new(9999), t.priority == "urgent" ? 0 : 1] }
    end

    def seconds_today
      @seconds_today ||= sessions_between(Date.current, Date.current).values.sum
    end

    def seconds_this_week
      @seconds_this_week ||= trend.sum { |_day, seconds| seconds }
    end

    # [[date, seconds], ...] for the trailing week, zero-filled.
    def trend
      @trend ||= begin
        days = (TREND_DAYS - 1).days.ago.to_date..Date.current
        logged = sessions_between(days.first, days.last)
        days.map { |day| [day, logged[day].to_i] }
      end
    end

    def completed_count
      count_for("completed")
    end

    def on_time_rate
      return nil if completed_count.zero?

      within = Task.for_executive(@user).where(status: "completed", over_sla: false).count
      (within * 100.0 / completed_count).round
    end

    private

    def sessions_between(from, to)
      TaskWorkSession.where(user_id: @user.id, started_at: from.beginning_of_day..to.end_of_day)
                     .group(Arel.sql("DATE(started_at)")).sum(:duration_seconds)
                     .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
    end
  end
end

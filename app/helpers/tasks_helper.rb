module TasksHelper
  # The four task statuses as fixed display roles. The colours are the
  # validated set documented at the top of _task_manager.scss — slate for "not
  # started" is the de-emphasis colour, and the three meaningful hues were
  # checked as a group for colour-vision separation. Never reassign these by
  # filter state: a reader who learned that blue means running must not find it
  # meaning something else after filtering.
  STATUS_ROLES = {
    "pending" => { label: "Not started", color: "#7c8798" },
    "in_progress" => { label: "Running", color: "#2a78d6" },
    "paused" => { label: "Paused", color: "#eb6834" },
    "completed" => { label: "Done", color: "#1baf7a" }
  }.freeze

  def task_status_label(status)
    STATUS_ROLES.dig(status.to_s, :label) || status.to_s.humanize
  end

  def task_status_color(status)
    STATUS_ROLES.dig(status.to_s, :color) || "#7c8798"
  end

  def task_status_badge(status)
    tag.span task_status_label(status), class: "tm-badge tm-badge--#{status}"
  end

  def hours_label(seconds, blank: "—")
    seconds = seconds.to_i
    return blank if seconds.zero?

    h, rem = seconds.divmod(3600)
    m, = rem.divmod(60)
    h.positive? ? "#{h}h #{m}m" : "#{m}m"
  end

  # Hours as a decimal, for chart axes where "1h 30m" cannot be plotted.
  def hours_decimal(seconds)
    (seconds.to_i / 3600.0).round(2)
  end

  def initials_for(user)
    return "?" if user.blank?
    return user.initials if user.respond_to?(:initials) && user.initials.present?

    user.name.to_s.split.first(2).map { |part| part[0] }.join.upcase.presence || "?"
  end

  def task_avatar(user, size: nil)
    tag.span initials_for(user),
             class: ["tm-avatar", size == :lg ? "tm-avatar--lg" : nil].compact,
             title: user&.name
  end

  # "4 minutes ago" for anything recent, an absolute date once it stops being
  # useful to count back — a comment thread reads by relative time, history
  # reads by date.
  def task_time_ago(time)
    return "" if time.blank?

    if time > 6.days.ago
      "#{time_ago_in_words(time)} ago"
    else
      time.strftime("%d %b %Y, %H:%M")
    end
  end

  def task_due_label(task)
    return "No due date" if task.due_date.blank?

    days = (task.due_date - Date.current).to_i
    case days
    when 0 then "Due today"
    when 1 then "Due tomorrow"
    when -1 then "1 day overdue"
    else
      days.negative? ? "#{-days} days overdue" : "Due #{task.due_date.strftime('%d %b')}"
    end
  end

  def task_overdue?(task)
    task.due_date.present? && !task.completed? && task.due_date < Date.current
  end

  # How much of a task's time budget is spent, as a percentage capped at 100 —
  # the bar cannot overflow its track, the "over" colour carries the breach.
  def sla_percentage(task, seconds = nil)
    budget = task.sla_seconds
    return 0 if budget.zero?

    logged = seconds || task.rolled_up_duration_seconds
    [(logged * 100.0 / budget).round, 100].min
  end

  def sla_meter_class(task, seconds = nil)
    return "tm-meter__fill--over" if task.over_sla?
    return "tm-meter__fill--done" if task.completed?

    sla_percentage(task, seconds) >= 80 ? "tm-meter__fill--warn" : ""
  end

  # "Client — Project" optgroups holding that project's sprints, so a manager
  # picks the client and the cycle in one control.
  def sprint_options_grouped_by_project(sprints = @sprints)
    sprints.group_by(&:project).map do |project, project_sprints|
      ["#{project.client.name} — #{project.name}",
       project_sprints.map { |s| [s.name, s.id] }]
    end
  end

  def sprint_label(sprint)
    return nil if sprint.blank?

    "#{sprint.project.client.name} / #{sprint.project.name} / #{sprint.name}"
  end

  # --- Chart specs ---------------------------------------------------------
  # The canvas carries its spec as JSON and task_manager.js builds the chart
  # from it, so no view ever writes chart code inline. That is what let the
  # previous version's chart script get split across two partials and break.

  def chart_spec(spec)
    spec.to_json
  end

  def workload_chart_spec(rows)
    {
      kind: "workload",
      labels: rows.map(&:first),
      series: STATUS_ROLES.map do |status, role|
        { label: role[:label], color: role[:color],
          data: rows.map { |(_name, counts)| counts[status].to_i } }
      end
    }
  end

  def throughput_chart_spec(points)
    {
      kind: "trend",
      labels: points.map { |day, _| day.strftime("%-d %b") },
      data: points.map(&:last),
      color: "#2a78d6",
      fill: "rgba(42, 120, 214, 0.10)",
      unit: "completed"
    }
  end

  def hours_chart_spec(points)
    {
      kind: "columns",
      labels: points.map { |day, _| day.strftime("%a") },
      data: points.map { |_, seconds| hours_decimal(seconds) },
      formatted: points.map { |_, seconds| hours_label(seconds, blank: "nothing logged") },
      color: "#2a78d6"
    }
  end
end

# A task a Manager assigns to one of their direct-report Executives, with a
# start/pause/resume/complete timer. Pausing can happen two ways: manually by
# the executive (`auto_paused: false`), or automatically because their
# TimeClock break started (`auto_paused: true`, see TaskBreakSync) — only the
# latter gets auto-resumed when the break ends.
class Task < ApplicationRecord
  belongs_to :assigned_to, class_name: "User" # Executive
  belongs_to :assigned_by, class_name: "User" # Manager
  belongs_to :task_type
  has_many :work_sessions, class_name: "TaskWorkSession", dependent: :destroy
  belongs_to :parent, class_name: "Task", optional: true
  has_many :subtasks, class_name: "Task", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent

  enum status: { pending: "pending", in_progress: "in_progress", paused: "paused", completed: "completed" },
       _default: "pending"

  PRIORITIES = %w[normal urgent].freeze

  validates :title, presence: true
  validates :priority, inclusion: { in: PRIORITIES }
  validate :assigned_to_is_a_direct_report_executive
  validate :parent_is_not_a_subtask
  validate :task_type_belongs_to_managers_department

  scope :active, -> { where(status: %w[in_progress paused]) }
  scope :for_manager, ->(user) { where(assigned_by: user) }
  scope :for_executive, ->(user) { where(assigned_to: user) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :subtasks_only, -> { where.not(parent_id: nil) }

  def subtask? = parent_id.present?
  def parent_task? = subtasks.any?

  # A parent's real cost is its own logged time plus everything its children
  # logged — including children assigned to a different executive.
  def rolled_up_duration_seconds
    live_duration_seconds + subtasks.sum(&:live_duration_seconds)
  end

  def subtask_progress
    children = subtasks.to_a
    [children.count(&:completed?), children.size]
  end

  def may_start? = pending?
  def may_pause? = in_progress?
  def may_resume? = paused?
  def may_complete? = in_progress? || paused?

  def start!
    return false unless may_start?

    transaction do
      update!(status: :in_progress, started_at: Time.current)
      TaskWorkSession.open_for(self)
    end
    true
  end

  def pause!(reason: nil, auto: false)
    return false unless may_pause?

    transaction do
      TaskWorkSession.close_for(self)
      update!(status: :paused, pause_time: Time.current, reason: reason, auto_paused: auto)
    end
    true
  end

  def resume!
    return false unless may_resume?

    elapsed = pause_time.present? ? (Time.current - pause_time).to_i : 0
    transaction do
      update!(
        status: :in_progress,
        resume_time: Time.current,
        accumulated_pause_seconds: accumulated_pause_seconds + elapsed,
        pause_time: nil,
        auto_paused: false,
        reason: nil
      )
      TaskWorkSession.open_for(self)
    end
    true
  end

  def complete!
    return false unless may_complete?

    now = Time.current
    extra_pause = paused? && pause_time.present? ? (now - pause_time).to_i : 0

    transaction do
      TaskWorkSession.close_for(self, at: now)
      session_total = work_sessions.reload.sum(:duration_seconds)
      # A task that was already in progress when this table shipped has no
      # sessions to sum, so fall back to the original elapsed-minus-pauses
      # arithmetic rather than recording it as zero hours.
      final_duration = if session_total.positive?
                         session_total
                       else
                         (now - started_at).to_i - (accumulated_pause_seconds + extra_pause)
                       end
      update!(
        status: :completed,
        ended_at: now,
        accumulated_pause_seconds: accumulated_pause_seconds + extra_pause,
        total_duration: final_duration,
        over_sla: sla_seconds.positive? && final_duration > sla_seconds
      )
    end
    true
  end

  # A manager can override the task type's default SLA per task at creation
  # time (custom_sla_minutes) — the type's value is just the starting point,
  # not a hard rule, similar to how a ClickUp task's time estimate can diverge
  # from its template's default.
  def sla_minutes
    custom_sla_minutes || task_type&.sla_minutes.to_i
  end

  def sla_seconds
    sla_minutes.to_i * 60
  end

  def formatted_sla
    h, m = sla_minutes.to_i.divmod(60)
    h.positive? ? "#{h}h #{m}m" : "#{m}m"
  end

  # Live for active tasks (recomputed from the current elapsed duration),
  # persisted for completed ones (set once in complete! and never revisited).
  def over_sla?
    return over_sla if completed?
    return false if sla_seconds.zero?

    live_duration_seconds > sla_seconds
  end

  # Elapsed working seconds as of right now, excluding paused time. Not
  # memoized — the live ticking display recomputes this client-side every
  # second from started_at/accumulated_pause_seconds, this is just the
  # server-rendered starting point (and the value used once a task is done).
  def live_duration_seconds
    return total_duration || 0 if completed?
    return 0 if started_at.blank?

    end_point = paused? && pause_time.present? ? pause_time : Time.current
    [(end_point - started_at).to_i - accumulated_pause_seconds, 0].max
  end

  def formatted_duration(seconds = live_duration_seconds)
    h, rem = seconds.to_i.divmod(3600)
    m, = rem.divmod(60)
    format("%dh %dm", h, m)
  end

  private

  # Jira and ClickUp both stop at one level of nesting, and so do we: deeper
  # trees make the rollup recursive and the CSV parent column ambiguous.
  def parent_is_not_a_subtask
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent, "cannot be the task itself")
    elsif parent&.parent_id.present?
      errors.add(:parent, "cannot be a subtask itself")
    end
  end

  def assigned_to_is_a_direct_report_executive
    return if assigned_by.blank? || assigned_to.blank?

    unless assigned_by.direct_reports.include?(assigned_to)
      errors.add(:assigned_to, "must be one of your direct-report executives")
    end

    unless assigned_to.access_role&.name == "Executive"
      errors.add(:assigned_to, "must hold the Executive role")
    end
  end

  def task_type_belongs_to_managers_department
    return if task_type.blank? || assigned_by.blank?

    unless task_type.department_id == assigned_by.department_id
      errors.add(:task_type, "must belong to your department")
    end
  end
end

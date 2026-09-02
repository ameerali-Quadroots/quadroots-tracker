# One uninterrupted stretch of work on a task, written by the Task timer on
# start/pause/resume/complete. Sessions are the source of truth for *when* time
# was spent; Task#total_duration is only a cached rollup of them.
#
# A session is split at every midnight when it closes, so summing hours per day
# is a plain GROUP BY DATE(started_at) with no date arithmetic in the query.
class TaskWorkSession < ApplicationRecord
  belongs_to :task
  belongs_to :user

  validates :started_at, presence: true

  scope :open_sessions, -> { where(ended_at: nil) }
  scope :closed_sessions, -> { where.not(ended_at: nil) }

  # Splits [start_time, end_time) at each local midnight.
  # Returns [] for an empty or backwards interval.
  def self.segments(start_time, end_time)
    return [] if start_time.blank? || end_time.blank? || end_time <= start_time

    segments = []
    cursor = start_time
    while cursor < end_time
      next_midnight = cursor.in_time_zone.beginning_of_day + 1.day
      stop = [next_midnight, end_time].min
      segments << [cursor, stop]
      cursor = stop
    end
    segments
  end

  # Gives tasks completed before this table existed a session each, so historic
  # weeks are not blank on the hours report. The interval is reconstructed
  # backwards from ended_at, which is the only timestamp we can trust — a task
  # paused for two days has a started_at that does not reflect worked time.
  def self.backfill_completed_tasks!
    scope = Task.where(status: "completed")
                .where.not(ended_at: nil)
                .where(total_duration: 1..)
                .where.missing(:work_sessions)

    count = 0
    scope.find_each do |task|
      ends_at = task.ended_at.in_time_zone
      starts_at = ends_at - task.total_duration.seconds

      segments(starts_at, ends_at).each do |from, to|
        create!(task_id: task.id, user_id: task.assigned_to_id, started_at: from,
                ended_at: to, duration_seconds: (to - from).round)
      end
      count += 1
    end
    count
  end

  def self.open_for(task, at: Time.current)
    create!(task_id: task.id, user_id: task.assigned_to_id, started_at: at)
  end

  # Closes the task's most recent open session. Nil when none is open — which
  # happens for tasks that predate this table, so callers must tolerate it.
  def self.close_for(task, at: Time.current)
    session = where(task_id: task.id).open_sessions.order(:started_at).last
    session&.close!(at)
  end

  # Closes this session at `at`. The first day's slice updates this row; each
  # later day becomes its own row.
  def close!(at)
    slices = self.class.segments(started_at, at)
    if slices.empty?
      update!(ended_at: started_at, duration_seconds: 0)
      return self
    end

    transaction do
      first_from, first_to = slices.shift
      update!(ended_at: first_to, duration_seconds: (first_to - first_from).round)

      slices.each do |from, to|
        self.class.create!(task_id: task_id, user_id: user_id, started_at: from,
                           ended_at: to, duration_seconds: (to - from).round)
      end
    end
    self
  end
end

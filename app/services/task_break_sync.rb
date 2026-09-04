# Keeps an employee's own Task timers in sync with their own TimeClock state.
# Scoped to one employee only — never touches another user's tasks — and only
# auto-resumes a task it auto-paused itself, so a task the executive had
# manually paused for some other reason stays paused after the break ends.
class TaskBreakSync
  def self.pause_for_break(employee)
    Task.for_executive(employee).in_progress.first&.pause!(reason: "Auto-paused: break started", auto: true)
  end

  def self.resume_after_break(employee)
    Task.for_executive(employee).paused.where(auto_paused: true).first&.resume!
  end

  # The shift is over, so nothing may keep accruing time: a task left running
  # on Friday would otherwise log the whole weekend. Recorded as a manual pause
  # (auto: false) deliberately — a clock-out pause must not be undone by the
  # next break ending tomorrow.
  #
  # One task can fail to pause (a task whose assignee has since changed
  # department no longer validates) without taking the clock-out down with it,
  # so each is attempted on its own and a failure is logged, not raised.
  def self.pause_for_clock_out(employee)
    Task.for_executive(employee).in_progress.each do |task|
      task.pause!(reason: "Clocked out — timer stopped for the shift")
    rescue StandardError => e
      Rails.logger.error "TaskBreakSync could not pause task #{task.id} on clock out: #{e.message}"
    end
  end
end

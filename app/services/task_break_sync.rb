# Keeps an employee's own in_progress Task in sync with their own TimeClock
# break state. Scoped to one employee only — never touches another user's
# tasks — and only auto-resumes a task it auto-paused itself, so a task the
# executive had manually paused for some other reason stays paused after the
# break ends.
class TaskBreakSync
  def self.pause_for_break(employee)
    Task.for_executive(employee).in_progress.first&.pause!(reason: "Auto-paused: break started", auto: true)
  end

  def self.resume_after_break(employee)
    Task.for_executive(employee).paused.where(auto_paused: true).first&.resume!
  end
end

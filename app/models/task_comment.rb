# A note left on a task by the manager who owns it or the executive doing it.
# Comments are the module's discussion channel: they never change a task's
# state, so anyone who can see the task can add one.
class TaskComment < ApplicationRecord
  MAX_LENGTH = 5_000

  belongs_to :task, counter_cache: :comments_count
  belongs_to :user

  validates :body, presence: true, length: { maximum: MAX_LENGTH }

  scope :chronological, -> { order(:created_at) }

  before_validation :squeeze_body

  # A comment is editable only by its author, and only while it is still fresh
  # enough to read as a correction rather than a rewrite of history.
  EDIT_WINDOW = 15.minutes

  def editable_by?(other)
    user_id == other&.id && created_at.present? && created_at > EDIT_WINDOW.ago
  end

  def deletable_by?(other)
    user_id == other&.id
  end

  private

  # Trailing blank lines from a textarea would otherwise stretch every row in
  # the thread.
  def squeeze_body
    self.body = body.to_s.strip.gsub(/\n{3,}/, "\n\n")
  end
end

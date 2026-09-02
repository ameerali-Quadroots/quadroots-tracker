# One delivery cycle of a project, normally a week. Tasks point at a sprint
# optionally, so ad-hoc work that belongs to no sprint keeps working unchanged.
class Sprint < ApplicationRecord
  STATUSES = %w[planned active completed].freeze

  belongs_to :project
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :start_date, :end_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_date_after_start_date

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(start_date: :desc) }
  scope :for_department, ->(department_id) {
    joins(project: :client).where(clients: { department_id: department_id })
  }

  delegate :department, :department_id, :client, to: :project

  def to_s = name

  def progress
    rows = tasks.to_a
    [rows.count { |t| t.status == "completed" }, rows.size]
  end

  def logged_seconds
    TaskWorkSession.where(task_id: tasks.select(:id)).sum(:duration_seconds)
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be on or after the start date") if end_date < start_date
  end
end

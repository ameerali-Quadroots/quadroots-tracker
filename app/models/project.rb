# A body of work for one client — "CRM", "Website rebuild". Weekly sprints hang
# off a project, so a multi-week build stays one thing with many cycles.
class Project < ApplicationRecord
  STATUSES = %w[planned active on_hold completed].freeze

  belongs_to :client
  has_many :sprints, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :client_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:name) }

  delegate :department, :department_id, to: :client

  def to_s = name
end

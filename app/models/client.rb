# A customer the department does work for. Clients are department-scoped: the
# same company can appear under Web and under Design as separate rows, because
# each department runs its own engagement.
class Client < ApplicationRecord
  belongs_to :department
  has_many :projects, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :department_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  def to_s = name
end

class TaskType < ApplicationRecord
  belongs_to :department
  has_many :tasks, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :department_id }
  validates :sla_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def formatted_sla
    h, m = sla_minutes.divmod(60)
    h.positive? ? "#{h}h #{m}m" : "#{m}m"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name department_id sla_minutes created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[department tasks]
  end
end

class Department < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :admin_users, dependent: :nullify
  has_many :task_types, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_destroy :ensure_no_members, prepend: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def to_s
    name
  end

  def member_count
    users.count + admin_users.count
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name code position active task_manager_enabled created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[users admin_users task_types]
  end

  private

  # Deleting a department would silently orphan everyone in it, so make the
  # admin move them out first.
  def ensure_no_members
    return if member_count.zero?

    errors.add(:base, "#{name} still has #{member_count} member(s). Move them to another department first.")
    throw :abort
  end
end

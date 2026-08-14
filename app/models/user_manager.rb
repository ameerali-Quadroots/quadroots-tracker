# A single "reports to" edge. Employees can have more than one manager (e.g.
# a dotted-line report to a second executive), so the reporting line is a
# graph rather than a single `reports_to_id` column - this join table is the
# source of truth. `users.reports_to_id` is kept as a synced "primary
# manager" convenience column for the few places that only need one.
class UserManager < ApplicationRecord
  belongs_to :user
  belongs_to :manager, class_name: "User"

  validates :manager_id, uniqueness: { scope: :user_id, message: "is already a manager for this employee" }
  validate :manager_is_not_self
  validate :assignment_must_not_create_a_cycle

  after_save :sync_primary_manager
  after_destroy :sync_primary_manager

  def self.ransackable_attributes(auth_object = nil)
    %w[id user_id manager_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user manager]
  end

  private

  def manager_is_not_self
    return if manager_id.blank? || user_id.blank?

    errors.add(:manager_id, "cannot be the employee themselves") if manager_id == user_id
  end

  # A cycle would form if the proposed manager already reports, directly or
  # transitively, to this user - i.e. this user is already one of the
  # manager's managers.
  def assignment_must_not_create_a_cycle
    return if manager.blank? || user.blank? || manager_id == user_id

    errors.add(:manager_id, "would create a reporting loop") if manager.manager_ids.include?(user_id)
  end

  def sync_primary_manager
    return if user.blank?

    primary_id = user.reporting_relationships.order(:id).first&.manager_id
    user.update_column(:reports_to_id, primary_id) if user.reports_to_id != primary_id
  end
end

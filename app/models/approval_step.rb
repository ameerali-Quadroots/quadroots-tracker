class ApprovalStep < ApplicationRecord
  belongs_to :approval_flow
  belongs_to :role
  has_many :approvals, dependent: :destroy

  validates :position, numericality: { only_integer: true }

  before_validation :default_name

  def to_s
    name.presence || role&.name.to_s
  end

  # A step filled from the admin panel rather than by an employee: no User
  # holds an admin-scope role, so only an AdminUser can settle it.
  def admin_step?
    role&.scope == "admin"
  end

  # Who should act on this step for a given requester: the nearest person above
  # them in the reporting tree holding this step's role. Falls back to anyone
  # active with the role in the requester's department, then anyone with the
  # role at all - so a half-filled organogram still routes somewhere.
  def approver_for(requester)
    return nil if requester.blank? || admin_step?

    requester.nearest_manager_with_role(role) ||
      User.employed.where(role_id: role_id, department_id: requester.department_id).where.not(id: requester.id).first ||
      User.employed.where(role_id: role_id).where.not(id: requester.id).first
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id approval_flow_id role_id name position optional created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[approval_flow role approvals]
  end

  private

  def default_name
    self.name = role&.name if name.blank?
  end
end

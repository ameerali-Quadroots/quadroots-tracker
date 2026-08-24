class Approval < ApplicationRecord
  STATUSES = %w[pending approved rejected skipped].freeze

  belongs_to :approvable, polymorphic: true
  belongs_to :approval_step
  belongs_to :approver, polymorphic: true, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position, :id) }
  scope :pending, -> { where(status: "pending") }
  scope :decided, -> { where.not(status: "pending") }

  delegate :role, to: :approval_step, allow_nil: true

  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def skipped?  = status == "skipped"

  def role_name
    approval_step&.to_s
  end

  # Who settled this step, as one printable label. The approver is polymorphic:
  # an employee (User, which has a `name`) when the step was actioned from the
  # app, or an AdminUser (email only, no name column at all) when an admin
  # approved or force-approved it from the admin panel. Callers must not assume
  # `name` exists on whatever comes back from `approver`.
  def approver_name
    return nil if approver.blank?

    approver.try(:name).presence || approver.try(:email).presence
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id approvable_type approvable_id approval_step_id approver_type approver_id
       status position note acted_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[approvable approval_step approver]
  end
end

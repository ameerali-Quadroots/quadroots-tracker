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

  def self.ransackable_attributes(auth_object = nil)
    %w[id approvable_type approvable_id approval_step_id approver_type approver_id
       status position note acted_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[approvable approval_step approver]
  end
end

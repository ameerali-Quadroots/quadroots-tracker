# Drives a record through an admin-configured chain of approval steps
# (Settings -> Approval Flows), instead of the two hardcoded manager/admin
# stages the app used before.
#
# The legacy `approved_by_manager` / `approved_by_admin` / `status` columns are
# kept in sync as the chain advances, so the existing employee views and
# ActiveAdmin screens keep working unchanged:
#   approved_by_manager = at least one step approved
#   approved_by_admin   = the whole chain approved
module Approvable
  extend ActiveSupport::Concern

  included do
    has_many :approvals, -> { ordered }, as: :approvable, dependent: :destroy
    has_many :approval_steps_taken, through: :approvals, source: :approval_step

    after_create :build_approvals!
  end

  # Creates one pending approval per step of the matching flow.
  def build_approvals!
    return if approvals.any?

    flow = approval_flow
    return if flow.nil?

    flow.approval_steps.each_with_index do |step, index|
      approvals.create!(approval_step: step, position: index, status: "pending")
    end
  end

  def approval_flow
    ApprovalFlow.for(self.class.name, try(:request_type))
  end

  # The step currently waiting on someone.
  def current_approval
    approvals.ordered.detect(&:pending?)
  end

  def current_step
    current_approval&.approval_step
  end

  def current_role
    current_step&.role
  end

  # Who is expected to act next.
  def current_approver
    current_step&.approver_for(requester)
  end

  # Chain finished with every step approved.
  def fully_approved?
    approvals.any? && approvals.none? { |a| a.pending? || a.rejected? }
  end

  def chain_rejected?
    approvals.any?(&:rejected?)
  end

  # Can this user act on the step that is currently waiting?
  # They must hold the step's role and sit above the requester in the tree
  # (or be the resolved approver for it).
  def actionable_by?(user)
    return false if user.blank?

    approval = current_approval
    return false if approval.nil?
    return false if user.role_id != approval.approval_step.role_id
    return false if requester.present? && user.id == requester.id

    user.manages?(requester) || approval.approval_step.approver_for(requester)&.id == user.id
  end

  def approve!(by:, note: nil)
    approval = current_approval
    raise "No pending approval step" if approval.nil?

    transaction do
      approval.update!(status: "approved", approver: by, note: note, acted_at: Time.current)
      advance!
    end
    self
  end

  def reject!(by:, note: nil)
    approval = current_approval
    raise "No pending approval step" if approval.nil?

    transaction do
      approval.update!(status: "rejected", approver: by, note: note, acted_at: Time.current)
      # Everything after a rejection is moot.
      approvals.pending.update_all(status: "skipped", updated_at: Time.current)
      finalize!(approved: false)
      after_chain_rejected if respond_to?(:after_chain_rejected, true)
    end
    self
  end

  # Admin-panel override. Admins could always approve a request outright, and
  # they keep that power: this settles every remaining step in one action, and
  # still works on legacy requests that predate the chain.
  def force_approve!(by:, note: nil)
    transaction do
      approvals.pending.find_each do |a|
        a.update!(status: "approved", approver: by, note: note, acted_at: Time.current)
      end
      finalize!(approved: true)
      after_chain_approved if respond_to?(:after_chain_approved, true)
    end
    self
  end

  def force_reject!(by:, note: nil)
    transaction do
      current_approval&.update!(status: "rejected", approver: by, note: note, acted_at: Time.current)
      approvals.pending.update_all(status: "skipped", updated_at: Time.current)
      finalize!(approved: false)
      after_chain_rejected if respond_to?(:after_chain_rejected, true)
    end
    self
  end

  # The person the request is about. Overridable; defaults to `user`.
  def requester
    try(:user)
  end

  private

  # Skips steps nobody can fill, then finalises when the chain runs out.
  def advance!
    while (approval = current_approval)
      step = approval.approval_step
      break unless step.optional? && step.approver_for(requester).nil?

      approval.update!(status: "skipped", acted_at: Time.current)
    end

    if current_approval.nil?
      finalize!(approved: true)
      after_chain_approved if respond_to?(:after_chain_approved, true)
    else
      sync_legacy_columns!
    end
  end

  # Mid-chain: only the "a manager has signed off" flag moves.
  def sync_legacy_columns!
    return unless respond_to?(:approved_by_manager)

    update_columns(approved_by_manager: approvals.reload.any?(&:approved?), updated_at: Time.current)
  end

  # Terminal state, written to the legacy columns the existing views read.
  def finalize!(approved:)
    attrs = {}
    attrs[:approved_by_manager] = approved if respond_to?(:approved_by_manager)
    attrs[:approved_by_admin]   = approved if respond_to?(:approved_by_admin)
    attrs[:status]              = approved ? "approved" : "rejected" if respond_to?(:status)
    attrs[:resolved_at]         = Time.current if respond_to?(:resolved_at)

    update_columns(attrs.merge(updated_at: Time.current)) if attrs.any?
  end
end

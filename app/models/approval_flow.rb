class ApprovalFlow < ApplicationRecord
  SUBJECT_TYPES = %w[EditRequest Leave].freeze

  has_many :approval_steps, -> { order(:position, :id) }, dependent: :destroy
  has_many :roles, through: :approval_steps

  accepts_nested_attributes_for :approval_steps, allow_destroy: true,
                                reject_if: ->(attrs) { attrs[:role_id].blank? }

  validates :name, presence: true
  validates :subject_type, presence: true, inclusion: { in: SUBJECT_TYPES }
  validates :request_type, uniqueness: { scope: :subject_type,
                                         message: "already has a flow for this subject" }

  scope :active, -> { where(active: true) }

  # The admin form's "All (catch-all for this subject)" option posts request_type
  # as "". Left as-is, that permanently breaks `.for`'s `request_type: nil`
  # fallback lookup (an empty string never matches an IS NULL query), so the
  # catch-all silently stops catching anything.
  before_validation :nilify_blank_request_type

  def nilify_blank_request_type
    self.request_type = nil if request_type.blank?
  end
  private :nilify_blank_request_type

  # The flow that governs a record: the one matching its request_type, falling
  # back to the subject's catch-all flow (request_type nil).
  def self.for(subject_type, request_type = nil)
    active.find_by(subject_type: subject_type, request_type: request_type) ||
      active.find_by(subject_type: subject_type, request_type: nil)
  end

  def to_s
    name
  end

  def summary
    return "No steps - approves immediately" if approval_steps.empty?

    approval_steps.map.with_index(1) { |s, i| "#{i}. #{s}" }.join("  →  ")
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name subject_type request_type active created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[approval_steps roles]
  end
end

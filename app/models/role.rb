class Role < ApplicationRecord
  SCOPES = %w[employee admin both].freeze

  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :users, dependent: :nullify
  has_many :admin_users, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :scope, inclusion: { in: SCOPES }
  validates :rank, numericality: { only_integer: true }

  before_validation :set_slug
  before_destroy :ensure_not_system, prepend: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:rank, :name) }

  # Roles usable by a given login. "both" roles show up in either list.
  scope :for_scope, ->(scope) { where(scope: [scope.to_s, "both"]) }

  def to_s
    name
  end

  # The super_admin role keeps unconditional access regardless of the matrix,
  # so an admin cannot accidentally lock everyone out of the panel.
  def super_admin?
    system? && slug == "super_admin"
  end

  # Page permissions, e.g. permits?("team_status")
  def permits?(key)
    permission_keys.include?(key.to_s)
  end

  # Resource permissions, e.g. can?(:update, "EditRequest")
  def can?(action, subject)
    return true if super_admin?

    permission_keys.include?(Permission.resource_key(subject, action))
  end

  def permission_keys
    @permission_keys ||= permissions.pluck(:key).to_set
  end

  def reload(*)
    @permission_keys = nil
    super
  end

  def member_count
    users.count + admin_users.count
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name slug scope rank description system active created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[permissions role_permissions users admin_users]
  end

  private

  def set_slug
    self.slug = name.to_s.parameterize(separator: "_").presence || slug
  end

  def ensure_not_system
    return unless system?

    errors.add(:base, "#{name} is a system role and cannot be deleted.")
    throw :abort
  end
end

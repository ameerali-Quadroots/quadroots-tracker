class User < ApplicationRecord
    has_one_attached :image
    has_many :leaves, dependent: :destroy
    has_many :push_subscriptions, dependent: :destroy
    has_many :notifications, dependent: :destroy

  # Roles and departments are rows in `roles` / `departments`, managed from the
  # admin panel. The legacy `role` / `department` string columns are kept in
  # sync below so existing `user.role == "Manager"` checks keep working while
  # call sites migrate to permissions.
  belongs_to :access_role, class_name: "Role", foreign_key: :role_id, optional: true
  belongs_to :org_department, class_name: "Department", foreign_key: :department_id, optional: true

  # Reporting line. Drives the organogram, approval routing and team scoping.
  # An employee can have more than one manager (dotted-line reporting), so
  # this is a many-to-many graph via UserManager, not a single FK. `reports_to`
  # is kept as a synced "primary manager" convenience for call sites that only
  # need one (see UserManager#sync_primary_manager).
  belongs_to :reports_to, class_name: "User", optional: true

  has_many :reporting_relationships, class_name: "UserManager", foreign_key: :user_id, dependent: :destroy, inverse_of: :user
  has_many :managers, through: :reporting_relationships

  has_many :managed_relationships, class_name: "UserManager", foreign_key: :manager_id, dependent: :destroy, inverse_of: :manager
  has_many :direct_reports, through: :managed_relationships, source: :user

  before_save :sync_legacy_role_and_department

  has_many :time_clocks, foreign_key: "user_id", dependent: :destroy
  has_many :edit_requests

  # Task Manager: this user as the Manager who assigned a task, and as the
  # Executive it was assigned to.
  has_many :tasks_assigned, class_name: "Task", foreign_key: "assigned_by_id", dependent: :destroy
  has_many :tasks, class_name: "Task", foreign_key: "assigned_to_id", dependent: :destroy


  scope :employed, -> { where(employeed: true) }


  # Devise modules
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable
  validates :password, presence: true, confirmation: true, if: :password_required?

  validate :acceptable_image

  # Helper method for checking admin
  def admin?
    role == 'admin'
  end

  # Kept only as a fallback for accounts that are not yet placed in the
  # organogram; the reporting tree is the source of truth now.
  HOD_MANAGED_DEPARTMENTS = ["WEB", "SEO", "ADS", "CONTENT"].freeze

  # Two-letter initials used as an avatar fallback when no image is attached.
  def initials
    name.to_s.split.map(&:first).join[0, 2].upcase.presence || "?"
  end

  # Where this user's feedback should be directed. Managers of the
  # HOD-managed departments give feedback to the HODs; everyone else
  # gives feedback within their own department.
  # A manager gives feedback to the department of whoever they report to
  # (their HOD); everyone else gives it within their own department. Derived
  # from the organogram, falling back to the old department list for anyone
  # not yet placed in the tree.
  def feedback_department
    return department unless manager_reporting_to_hod?

    hod_manager&.department.presence || "HOD'S"
  end

  # Whether this user gets the Feedback form. Managers who do not report up to
  # an HOD (e.g. HR, SALES, who report straight to the CEO) do not give it.
  def can_give_feedback?
    return true unless access_role&.name == "Manager" || self[:role] == "Manager"

    manager_reporting_to_hod?
  end

  # ---- Reporting line -------------------------------------------------

  # Options for the "Reports to" select: department managers and upper
  # management only (Manager rank or more senior - Manager, HOD, Director,
  # CEO), excluding the employee themselves. Executives and interns aren't
  # valid managers so they never show up here.
  def self.reporting_options(except: nil)
    manager_rank = Role.find_by(name: "Manager")&.rank

    scope = employed.includes(:access_role).order(:name)
    scope = scope.where.not(id: except.id) if except.respond_to?(:id) && except&.id.present?
    scope = scope.where(role_id: Role.where(scope: %w[employee both]).where("rank <= ?", manager_rank)) if manager_rank

    scope.map { |u| ["#{u.name} - #{u.access_role&.name || u[:role] || 'no role'}", u.id] }
  end

  # Everyone below this user in the reporting graph, at any depth, across
  # every branch a subordinate may sit in. Depth-capped so bad data (or a
  # validation that slipped through) can never spin forever.
  def subordinate_ids
    return [] if id.blank?

    sql = <<~SQL.squish
      WITH RECURSIVE tree AS (
        SELECT user_id, 1 AS depth FROM user_managers WHERE manager_id = :id
        UNION ALL
        SELECT um.user_id, t.depth + 1 FROM user_managers um
        INNER JOIN tree t ON um.manager_id = t.user_id
        WHERE t.depth < 20
      )
      SELECT DISTINCT user_id FROM tree
    SQL

    self.class.connection.select_values(self.class.sanitize_sql_array([sql, { id: id }]))
  end

  def subordinates
    User.where(id: subordinate_ids)
  end

  # Everyone above this user in the reporting graph, at any depth, across
  # every manager chain. Mirrors subordinate_ids.
  def manager_ids
    return [] if id.blank?

    sql = <<~SQL.squish
      WITH RECURSIVE tree AS (
        SELECT manager_id, 1 AS depth FROM user_managers WHERE user_id = :id
        UNION ALL
        SELECT um.manager_id, t.depth + 1 FROM user_managers um
        INNER JOIN tree t ON um.user_id = t.manager_id
        WHERE t.depth < 20
      )
      SELECT DISTINCT manager_id FROM tree
    SQL

    self.class.connection.select_values(self.class.sanitize_sql_array([sql, { id: id }]))
  end

  def all_managers
    User.where(id: manager_ids)
  end

  # Whether this user is anywhere above `other` in the reporting graph.
  def manages?(other)
    return false if other.blank? || other.id == id

    subordinate_ids.include?(other.id)
  end

  # Nearest person above this user holding the given role, searched
  # breadth-first so a role held by any of several managers at the same
  # level is found before falling deeper up any single branch.
  def nearest_manager_with_role(role)
    return nil if role.blank?

    seen = Set.new([id])
    frontier = managers.to_a

    until frontier.empty?
      found = frontier.find { |m| m.role_id == role.id }
      return found if found

      frontier.each { |m| seen << m.id }
      frontier = frontier.flat_map(&:managers).uniq(&:id).reject { |m| seen.include?(m.id) }
    end

    nil
  end

  # ---- Permissions ----------------------------------------------------

  # Permission lookups. Everything the employee-facing app gates on should go
  # through these two, never through a hardcoded role name.
  def permits?(page_key)
    access_role&.permits?(page_key) || false
  end

  def can_access?(action, subject)
    access_role&.can?(action, subject) || false
  end

  # Keeps the legacy string columns and the new foreign keys pointing at the
  # same thing, in whichever direction the record was written.
  def sync_legacy_role_and_department
    if role_id.present?
      self[:role] = access_role&.name
    elsif self[:role].present?
      self.role_id = Role.where("LOWER(name) = ?", self[:role].to_s.downcase).pick(:id)
    end

    if department_id.present?
      self[:department] = org_department&.name
    elsif self[:department].present?
      self.department_id = Department.where("LOWER(name) = ?", self[:department].to_s.downcase).pick(:id)
    end
  end

  # True for a Manager who reports to an HOD (through any of their managers).
  # Falls back to the legacy department list when the reporting line has not
  # been filled in yet.
  def manager_reporting_to_hod?
    is_manager = (access_role&.name || self[:role]) == "Manager"
    return false unless is_manager

    if managers.any?
      hod_manager.present?
    else
      HOD_MANAGED_DEPARTMENTS.include?(self[:department])
    end
  end

  # The first of this user's managers who holds the HOD role, if any.
  def hod_manager
    managers.detect { |m| (m.access_role&.name || m[:role]) == "HOD" }
  end

  def acceptable_image
    return unless image.attached?

    unless image.blob.content_type.in?(%w[image/png image/jpeg image/jpg image/webp])
      errors.add(:image, "must be a PNG, JPG, or WEBP file")
    end

    if image.blob.byte_size > 5.megabytes
      errors.add(:image, "is too large (maximum is 5 MB)")
    end
  end
   def password_required?
    new_record? || password.present?
  end


  MEDICAL_LEAVE_ENTITLEMENT = 10
  CASUAL_LEAVE_ENTITLEMENT = 15

  # Count of approved leaves by type
  def medical_leaves_count
    leaves.where(leave_type: 'medical', status: 'approved').count
  end

  def casual_leaves_count
    leaves.where(leave_type: 'casual', status: 'approved').count
  end

   def half_days_count
    leaves.where(leave_type: 'half_day', status: 'approved').count
  end

  # Remaining leaves
  def remaining_medical_leaves
    MEDICAL_LEAVE_ENTITLEMENT - medical_leaves_count
  end

  def remaining_casual_leaves
    CASUAL_LEAVE_ENTITLEMENT - casual_leaves_count
  end

  # Calculate absent days: any rejected/pending leave with no time_clock record
 def absent_days_count
  absent_dates = leaves.where(status: ['rejected', 'pending']).flat_map do |l|
    (l.start_date..l.end_date).to_a
  end.uniq

  absent_dates.count do |date|
    !time_clocks.exists?(clock_in: date.beginning_of_day..date.end_of_day)
  end
end


  def self.ransackable_attributes(auth_object = nil)
    ["name", "email", "phone_number", "address", "department", "role", "employeed", "role_id", "department_id", "reports_to_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["time_clocks", "access_role", "org_department", "managers", "direct_reports"]
  end
end

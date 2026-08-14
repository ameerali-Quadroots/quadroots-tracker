class AdminUser < ApplicationRecord
  # Roles live in the `roles` table and are managed from the admin panel.
  # The legacy `role` / `department` strings are kept in sync so existing
  # checks (and any stored filters) keep working.
  belongs_to :access_role, class_name: "Role", foreign_key: :role_id, optional: true
  belongs_to :org_department, class_name: "Department", foreign_key: :department_id, optional: true

  before_save :sync_legacy_role_and_department

  # Devise modules
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable
  validates :password, presence: true, confirmation: true, if: :password_required?

  # Role check helpers. These now read the linked role, falling back to the
  # legacy string for any row not yet backfilled.
  def role_slug
    access_role&.slug || role.to_s
  end

  def super_admin?
    role_slug == 'super_admin'
  end

  def manage_admin?
    role_slug == 'manage_admin'
  end

  def admin?
    role_slug == 'admin'
  end

  def qa_admin?
    role_slug == 'qa_admin'
  end

  # Permission lookups used by Ability and the admin views.
  def permits?(page_key)
    access_role&.permits?(page_key) || false
  end

  def can_access?(action, subject)
    access_role&.can?(action, subject) || false
  end

  def password_required?
    new_record? || password.present?
  end

  def sync_legacy_role_and_department
    if role_id.present?
      self[:role] = access_role&.slug
    elsif self[:role].present?
      self.role_id = Role.where("LOWER(slug) = :v OR LOWER(name) = :v", v: self[:role].to_s.downcase).pick(:id)
    end

    if department_id.present?
      self[:department] = org_department&.name
    elsif self[:department].present?
      self.department_id = Department.where("LOWER(name) = ?", self[:department].to_s.downcase).pick(:id)
    end
  end

  # For ransack gem (if used in admin dashboards like ActiveAdmin)
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "email", "encrypted_password", "id", "remember_created_at", "reset_password_sent_at", "reset_password_token", "updated_at", "role", "department", "role_id", "department_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["access_role", "org_department"]
  end
end

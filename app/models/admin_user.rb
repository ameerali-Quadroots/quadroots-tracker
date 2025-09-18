class AdminUser < ApplicationRecord
  enum role: { admin: "admin", super_admin: "super_admin", manage_admin: "manage_admin", qa_admin: "qa_admin" }

  # Devise modules
  devise :database_authenticatable, 
         :recoverable, :rememberable, :validatable

  # Role check helpers (recommended style)
  def super_admin?
    role == 'super_admin'
  end

  def manage_admin?
    role == 'manage_admin'
  end

  def admin?
    role == 'admin'
  end

  def qa_admin?
    role == 'qa_admin'
  end

  # For ransack gem (if used in admin dashboards like ActiveAdmin)
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "email", "encrypted_password", "id", "remember_created_at", "reset_password_sent_at", "reset_password_token", "updated_at"]
  end
end

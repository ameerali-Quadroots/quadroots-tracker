class RolePermission < ApplicationRecord
  belongs_to :role
  belongs_to :permission

  validates :permission_id, uniqueness: { scope: :role_id }

  def self.ransackable_attributes(auth_object = nil)
    %w[id role_id permission_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[role permission]
  end
end

class AdminDepartmentAccess < ApplicationRecord
  belongs_to :admin_user
  belongs_to :department

  validates :department_id, uniqueness: { scope: :admin_user_id }

  def self.ransackable_attributes(auth_object = nil)
    %w[id admin_user_id department_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[admin_user department]
  end
end

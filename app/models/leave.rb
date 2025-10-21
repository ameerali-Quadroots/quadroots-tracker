class Leave < ApplicationRecord
  belongs_to :user
  belongs_to :manager, class_name: 'User', foreign_key: 'approved_by', optional: true

  enum leave_type: { medical: 'medical', casual: 'casual' }
  enum status: { pending: 'pending', approved: 'approved', rejected: 'rejected' }

  validates :leave_type, presence: true
  validates :start_date, :end_date, presence: true
  validate :valid_date_range



  def self.ransackable_associations(auth_object = nil)
    ["manager", "user"]
  end

   def self.ransackable_attributes(auth_object = nil)
    ["manager_id","approved_by","approved_by_manager", "created_at", "end_date", "id", "id_value", "leave_type", "reason", "start_date", "status", "updated_at", "user_id"]
  end

  private

  def valid_date_range
    if start_date && end_date && end_date < start_date
      errors.add(:end_date, "must be after the start date")
    end
  end
end

class Leave < ApplicationRecord
  belongs_to :user
  belongs_to :manager, class_name: 'User', foreign_key: 'approved_by', optional: true

  enum leave_type: { medical: 'medical', casual: 'casual', half_day: "half_day" }
  enum status: { pending: 'pending', approved: 'approved', rejected: 'rejected' }

  validates :leave_type, presence: true
  validates :start_date, :end_date, presence: true
  validate :valid_date_range

    has_one_attached :medical_certificate

  validate :acceptable_medical_certificate



  


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

  def acceptable_medical_certificate
    return unless medical_certificate.attached?

    unless medical_certificate.content_type.in?(%w[image/jpeg image/png application/pdf])
      errors.add(:medical_certificate, "must be a JPEG, PNG, or PDF")
    end

    if medical_certificate.byte_size > 5.megabytes
      errors.add(:medical_certificate, "is too big. Maximum size allowed is 5MB.")
    end
  end
  
end

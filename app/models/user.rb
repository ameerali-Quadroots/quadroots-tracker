class User < ApplicationRecord
    has_one_attached :image
    has_many :leaves, dependent: :destroy
    has_many :push_subscriptions, dependent: :destroy
    has_many :notifications, dependent: :destroy

  enum role: { Executive: "Executive", Manager: "Manager", Director: "Director", Intern: "Intern" }

  has_many :time_clocks, foreign_key: "user_id", dependent: :destroy
  has_many :edit_requests


  scope :employed, -> { where(employeed: true) }


  # Devise modules
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable
  validates :password, presence: true, confirmation: true, if: :password_required?

  validate :acceptable_image

  # Helper method for checking admin
  def admin?
    role == 'admin'
  end

  # Departments whose managers report to the HODs.
  HOD_MANAGED_DEPARTMENTS = ["WEB", "SEO", "ADS", "CONTENT"].freeze

  # Two-letter initials used as an avatar fallback when no image is attached.
  def initials
    name.to_s.split.map(&:first).join[0, 2].upcase.presence || "?"
  end

  # Where this user's feedback should be directed. Managers of the
  # HOD-managed departments give feedback to the HODs; everyone else
  # gives feedback within their own department.
  def feedback_department
    if role == "Manager" && HOD_MANAGED_DEPARTMENTS.include?(department)
      "HOD'S"
    else
      department
    end
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
    ["name", "email", "phone_number", "address", "department", "role", "employeed"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["time_clocks"]
  end
end

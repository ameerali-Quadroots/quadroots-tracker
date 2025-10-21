class User < ApplicationRecord
    has_many :leaves, dependent: :destroy

  enum role: { Executive: "Executive", Manager: "Manager", Director: "Director", Intern: "Intern" }

  has_many :time_clocks
  has_many :edit_requests


  # Devise modules
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable
  validates :password, presence: true, confirmation: true, if: :password_required?
  # Helper method for checking admin
  def admin?
    role == 'admin'
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
    end

    absent_dates.count do |date|
      !time_clocks.exists?(clock_in: date.beginning_of_day..date.end_of_day)
    end
  end


  def self.ransackable_attributes(auth_object = nil)
    ["name", "email", "phone_number", "address", "department", "role"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["time_clocks"]
  end
end

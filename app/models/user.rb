class User < ApplicationRecord
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

  def self.ransackable_attributes(auth_object = nil)
    ["name", "email", "phone_number", "address", "department"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["time_clocks"]
  end
end

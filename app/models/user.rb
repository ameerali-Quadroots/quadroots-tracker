class User < ApplicationRecord
  enum role: { executive: "executive", manager: "manager" }

  has_many :time_clocks

  # Devise modules
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  # Helper method for checking admin
  def admin?
    role == 'admin'
  end

  def self.ransackable_attributes(auth_object = nil)
    ["name", "email", "phone_number", "address"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["time_clocks"]
  end
end

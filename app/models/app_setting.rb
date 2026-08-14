class AppSetting < ApplicationRecord
  validates :edit_request_monthly_limit, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # There's only ever one row; find it (creating with defaults if missing)
  # rather than making callers manage the singleton themselves.
  def self.instance
    first_or_create!
  end
end

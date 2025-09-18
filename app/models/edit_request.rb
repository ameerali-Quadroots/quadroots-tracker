class EditRequest < ApplicationRecord
  belongs_to :user
  belongs_to :time_clock

  enum status: { pending: "pending", approved: "approved", rejected: "rejected" }

  validates :requested_clock_in, presence: true
  validates :reason, presence: true
  validates :request_type, presence: true
  after_initialize :set_default_status, if: :new_record?


 def self.ransackable_attributes(auth_object = nil)
    ["request_type","approved_by_admin","approved_by_manager", "created_at", "department", "email", "id", "id_value", "manager_note",  "reason", "requested_clock_in", "resolved_at", "status", "time_clock_id", "updated_at", "user_id"]
  end

def self.ransackable_associations(auth_object = nil)
    ["time_clock", "user"]
  end

  private

  def set_default_status
    self.status ||= "pending"
  end

end

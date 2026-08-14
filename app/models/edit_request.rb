class EditRequest < ApplicationRecord
  include Approvable

  # Managers may only approve/reject a request within this window of its creation.
  MANAGER_ACTION_WINDOW = 1.week

  belongs_to :user
  belongs_to :time_clock

  enum status: { pending: "pending", approved: "approved", rejected: "rejected" }

  validates :requested_clock_in, presence: true
  validates :reason, presence: true
  validates :request_type, presence: true

  validate :within_monthly_limit, on: :create
  validate :requested_time_in_current_week, on: :create
  validate :time_clock_in_current_week, on: :create

  after_initialize :set_default_status, if: :new_record?

  # A manager can only act on the request while it is still within the action
  # window (one week from when it was submitted).
  def manager_actionable?
    created_at.nil? || created_at >= MANAGER_ACTION_WINDOW.ago
  end

  # Applies the correction to the time clock. Previously lived inline in
  # app/admin/edit_requests.rb; now the last approval in the chain triggers it,
  # whether that approval came from the admin panel or the tracker app.
  def apply_to_time_clock!
    return false if requested_clock_in.blank? || time_clock.blank?

    case request_type
    when "Clock tower not working"
      time_clock.update(clock_in: requested_clock_in, status: "on_time")
    when "Forgot to end break", "Forgot to add break"
      time_clock.breaks
                .where(break_type: break_reason)
                .update_all(break_out: requested_clock_in, updated_at: Time.current)
      # The break totals stored on the shift are now stale.
      time_clock.reload
      break_seconds = time_clock.total_break_seconds
      if time_clock.clock_out.present?
        time_clock.update_columns(
          break_duration: break_seconds,
          total_duration: [(time_clock.clock_out - time_clock.clock_in).to_i - break_seconds, 0].max,
          updated_at: Time.current
        )
      end
    end

    true
  end

  # Called by Approvable once every step has approved.
  def after_chain_approved
    apply_to_time_clock!
  end


 def self.ransackable_attributes(auth_object = nil)
    ["request_type","approved_by_admin","approved_by_manager", "created_at", "department", "email", "id", "id_value", "manager_note", "break_reason" , "reason", "requested_clock_in", "resolved_at", "status", "time_clock_id", "updated_at", "user_id"]
  end

def self.ransackable_associations(auth_object = nil)
    ["time_clock", "user"]
  end

  private

  def set_default_status
    self.status ||= "pending"
  end

  def within_monthly_limit
    return if user_id.blank?

    limit = AppSetting.instance.edit_request_monthly_limit
    month_range = Time.current.beginning_of_month..Time.current.end_of_month
    existing = user.edit_requests.where(created_at: month_range).count

    if existing >= limit
      errors.add(:base, "You have reached the limit of #{limit} edit requests for this month.")
    end
  end

  def requested_time_in_current_week
    return if requested_clock_in.blank?

    unless requested_clock_in.between?(Time.current.beginning_of_week, Time.current.end_of_week)
      errors.add(:requested_clock_in, "must be within the current week. You can't request edits for past dates.")
    end
  end

  def time_clock_in_current_week
    return if time_clock.blank? || time_clock.clock_in.blank?

    unless time_clock.clock_in.between?(Time.current.beginning_of_week, Time.current.end_of_week)
      errors.add(:base, "You can only request edits for the current week, not past records.")
    end
  end

end

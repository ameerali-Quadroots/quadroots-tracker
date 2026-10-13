# The record of one bulk late-mark correction: who ran it, for which shift day,
# why, and which time clocks went from "late" to "on_time". See
# TimeClocks::BulkCorrection, which creates these.
class BulkCorrection < ApplicationRecord
  belongs_to :admin_user
  belongs_to :undone_by, class_name: "AdminUser", optional: true

  validates :shift_date, :reason, :scope_label, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def undone?
    undone_at.present?
  end

  # Puts the corrected shifts back to late. Only shifts still on time are
  # touched, and only once: a second undo does nothing and returns false.
  def undo!(admin:)
    with_lock do
      next false if undone?

      TimeClock.where(id: time_clock_ids, status: "on_time").update_all(status: "late", updated_at: Time.current)
      update!(undone_at: Time.current, undone_by: admin)
      true
    end
  end
end

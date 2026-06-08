class NotificationService
  HR_EMAIL = "ali.raza@quadroots.com".freeze

  def self.notify_edit_request(edit_request)
    return unless pusher_configured?

    user = edit_request.user
    payload = {
      message: "#{user.name} submitted an edit request",
      requester_name: user.name,
      department: user.department,
      request_type: edit_request.request_type,
      submitted_at: edit_request.created_at.strftime("%b %d, %Y %I:%M %p")
    }

    trigger_for_recipients(user, "new-edit-request", payload)
  end

  def self.notify_leave_request(leave)
    return unless pusher_configured?

    user = leave.user
    payload = {
      message: "#{user.name} submitted a #{leave.leave_type.humanize} leave request",
      requester_name: user.name,
      department: user.department,
      leave_type: leave.leave_type,
      submitted_at: leave.created_at.strftime("%b %d, %Y %I:%M %p")
    }

    trigger_for_recipients(user, "new-leave-request", payload)
  end

  private

  def self.trigger_for_recipients(user, event, payload)
    recipients_for(user).each do |recipient|
      Pusher.trigger("private-user-#{recipient.id}", event, payload)
    end
  rescue Pusher::Error => e
    Rails.logger.error "Pusher notification failed: #{e.message}"
  end

  def self.recipients_for(user)
    recipients = []

    # Executive's request: notify their department Manager
    if user.role == "Executive"
      manager = User.find_by(role: "Manager", department: user.department, employeed: true)
      recipients << manager if manager
    end

    # HOD (Manager in HOD'S department) always notified
    hod = User.find_by(role: "Manager", department: "HOD'S", employeed: true)
    recipients << hod if hod

    # HR always notified
    hr = User.find_by(email: HR_EMAIL)
    recipients << hr if hr

    recipients.compact.uniq(&:id)
  end

  def self.pusher_configured?
    ENV['PUSHER_APP_ID'].present?
  end
end

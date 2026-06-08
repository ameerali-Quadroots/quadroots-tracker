class NotificationService
  HR_EMAIL = "ali.raza@quadroots.com".freeze

  def self.notify_edit_request(edit_request)
    user      = edit_request.user
    title     = "New Edit Request"
    message   = "#{user.name} (#{user.department}) submitted an edit request"
    url       = "/edit_requests"
    deliver(user, "new-edit-request", title, message, url)
    EditRequestMailer.new_request_notification(edit_request, recipient_emails_for(user)).deliver_later
  end

  def self.notify_leave_request(leave)
    user      = leave.user
    title     = "New Leave Request"
    message   = "#{user.name} (#{user.department}) submitted a #{leave.leave_type.humanize} leave request"
    url       = "/leaves"
    deliver(user, "new-leave-request", title, message, url)
    LeaveMailer.new_request_notification(leave, recipient_emails_for(user)).deliver_later
  end

  private

  def self.deliver(user, event, title, message, url)
    recipients_for(user).each do |recipient|
      recipient.notifications.create!(title: title, message: message, url: url)
      push_realtime(recipient, event, title: title, message: message, url: url)
      push_web(recipient, title, message, url)
    end
  end

  def self.push_realtime(recipient, event, payload)
    return unless ENV['PUSHER_APP_ID'].present?
    Pusher.trigger("private-user-#{recipient.id}", event, payload)
  rescue Pusher::Error => e
    Rails.logger.error "Pusher [user #{recipient.id}]: #{e.message}"
  end

  def self.push_web(recipient, title, body, url)
    return unless ENV['VAPID_PUBLIC_KEY'].present?
    vapid = {
      subject:     "mailto:#{ENV.fetch('VAPID_CONTACT_EMAIL', 'masfa@quadroots.com')}",
      public_key:  ENV['VAPID_PUBLIC_KEY'],
      private_key: ENV['VAPID_PRIVATE_KEY']
    }
    recipient.push_subscriptions.each do |sub|
      WebPush.payload_send(
        message:  { title: title, body: body, url: url, tag: title }.to_json,
        endpoint: sub.endpoint,
        p256dh:   sub.p256dh_key,
        auth:     sub.auth_key,
        vapid:    vapid
      )
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      sub.destroy
    rescue => e
      Rails.logger.error "WebPush [user #{recipient.id}]: #{e.message}"
    end
  end

  def self.recipients_for(user)
    recipients = []
    if user.role == "Executive"
      manager = User.find_by(role: "Manager", department: user.department, employeed: true)
      recipients << manager if manager
    end
    hod = User.find_by(role: "Manager", department: "HOD'S", employeed: true)
    recipients << hod if hod
    hr = User.find_by(email: HR_EMAIL)
    recipients << hr if hr
    recipients.compact.uniq(&:id)
  end

  def self.recipient_emails_for(user)
    recipients_for(user).map(&:email)
  end
end

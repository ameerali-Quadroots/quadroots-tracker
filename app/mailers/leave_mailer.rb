class LeaveMailer < ApplicationMailer
  def new_request_notification(leave, recipient_emails)
    @leave = leave
    mail(to: recipient_emails, subject: "New Leave Request Submitted")
  end
end

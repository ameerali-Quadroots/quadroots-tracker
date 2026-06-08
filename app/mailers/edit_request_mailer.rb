class EditRequestMailer < ApplicationMailer
  def new_request_notification(edit_request, recipient_emails)
    @edit_request = edit_request
    mail(to: recipient_emails, subject: "New Edit Request Submitted")
  end
end

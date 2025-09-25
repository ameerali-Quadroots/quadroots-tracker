class EditRequestMailer < ApplicationMailer
  def new_request_notification(edit_request, email)
    @edit_request = edit_request
    mail(
      to: "ameer@quadroots.com",
      subject: "New Edit Request Submitted"
    )
  end
end

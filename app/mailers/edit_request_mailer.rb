class EditRequestMailer < ApplicationMailer
  def new_request_notification(edit_request)
    @edit_request = edit_request
    email = User.where(department: @edit_request.department, role: "Manager").pluck(:email)

    mail(
      to: email,
      subject: "New Edit Request Submitted"
    )
  end
end

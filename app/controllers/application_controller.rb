class ApplicationController < ActionController::Base
  helper_method :can_view?

  private

  # Page-level authorization for the employee-facing app, driven by the role's
  # permission matrix (Settings -> Roles & Permissions) rather than a hardcoded
  # role name.
  def can_view?(page_key)
    current_user.present? && current_user.permits?(page_key)
  end

  def authorize_page!(page_key)
    return if can_view?(page_key)

    redirect_to root_path, alert: "You are not authorized to view that page."
  end
end

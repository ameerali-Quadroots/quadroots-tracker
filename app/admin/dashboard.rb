ActiveAdmin.register_page "Dashboard" do
  # Sidebar order is set explicitly on every item; without a priority
  # ActiveAdmin falls back to alphabetical, which buried the dashboard.
  menu priority: 1

  content do
    # Icons used by the dashboard partials. (Charts are drawn by active_admin.js.)
    div do
      raw "<link rel='stylesheet' href='https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css'>"
    end

    if current_admin_user.super_admin? || current_admin_user.qa_admin?
      div class: "height-class2" do
        render partial: 'admin/dashboard/super_admin_dashboard', locals: { current_admin_user: current_admin_user }
      end
    else
      div class: "height-class2" do
        departments_to_show = current_admin_user.viewable_department_names

        render partial: 'admin/dashboard/live_state_auto', locals: { departments: departments_to_show }
      end
    end
  end

  # Polled by the dashboard JS so the Live Command Center refreshes itself
  # without a full page reload.
  page_action :live_state, method: :get do
    departments_to_show =
      if current_admin_user.super_admin? || current_admin_user.qa_admin?
        User.distinct.pluck(:department).compact.sort
      else
        current_admin_user.viewable_department_names
      end

    render partial: 'admin/dashboard/live_state', locals: { departments: departments_to_show }, layout: false
  end

  # Returns just the Monthly Overview section for a given year, so the year
  # selector can swap it in via AJAX without a full page reload.
  page_action :monthly_overview, method: :get do
    unless current_admin_user.super_admin? || current_admin_user.qa_admin?
      render(plain: "Forbidden", status: :forbidden) and return
    end

    render partial: 'admin/dashboard/monthly_overview', locals: { year: params[:analytics_year] }, layout: false
  end
end

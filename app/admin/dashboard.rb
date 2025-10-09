ActiveAdmin.register_page "Dashboard" do
  content do
    div do
      raw "<script src='https://cdn.jsdelivr.net/npm/chart.js'></script>"
      raw "<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css' rel='stylesheet'>"
      raw "<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js'></script>"
    end
  

    if current_admin_user.super_admin? || current_admin_user.qa_admin?
      panel "Live Current State of Users by Department", class: "height-class2" do
        render partial: 'admin/dashboard/super_admin_dashboard', locals: { current_admin_user: current_admin_user }
      end
    else
      panel "Live Current State of Your Department", class: "height-class2" do
        # Special case for HOD'S
        departments_to_show =
          if current_admin_user.department == "HOD'S"
            %w[WEB SEO ADS CONTENT]
          else
            [current_admin_user.department].compact
          end

        render partial: 'admin/dashboard/live_state', locals: { departments: departments_to_show }
      end
    end
  end
end

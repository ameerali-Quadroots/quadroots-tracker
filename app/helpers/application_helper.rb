module ApplicationHelper
  def edit_requests_count
    if current_user.role == "Manager" && current_user.department != "HOD'S"
      EditRequest.where(department: current_user.department)
                 .where.not(user_id: current_user.id)
                 .count
    elsif current_user.department == "HOD'S"
      departments = ["WEB", "SEO", "ADS", "CONTENT"]
      manager_ids = User.where(role: "Manager", department: departments).pluck(:id)
      EditRequest.where(user_id: manager_ids).count
    else
      0
    end
  end

   def leaves_count
    if current_user.role == "Manager" && current_user.department != "HOD'S"
      # Regular Manager: sees Executives in their department
      Leave.joins(:user)
           .where(users: { role: "Executive", department: current_user.department })
           .count

    elsif current_user.role == "Manager" && current_user.department == "HOD'S"
      # HOD Manager: sees Managers from specific departments
      hod_departments = ["WEB", "SEO", "ADS", "CONTENT"]

      Leave.joins(:user)
           .where(users: { role: "Manager", department: hod_departments })
           .count

    else
      0
    end
    end
end

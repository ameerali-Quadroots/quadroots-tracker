ActiveAdmin.register_page "Dashboard" do
  content do
    today_range = Time.zone.now.beginning_of_day..Time.zone.now.end_of_day
    month_range = Time.zone.now.beginning_of_month..Time.zone.now.end_of_month

    total_users   = User.count
    on_time_today = TimeClock.where(status: 'on_time', clock_in: today_range).count
    late_today    = TimeClock.where(status: 'late', clock_in: today_range).count
    on_time_month = TimeClock.where(status: 'on_time', clock_in: month_range).count
    late_month    = TimeClock.where(status: 'late', clock_in: month_range).count

    # === Today’s Stats ===
    panel "Today’s Stats" do
      div style: "display: flex; gap: 30px; justify-content: space-around; margin: 20px 0;" do
        div style: "background:#3498db; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do
            total_users
          end
          span "Total Users"
        end

        div style: "background:#2ecc71; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do
            on_time_today
          end
          span "On Time Today"
        end

        div style: "background:#e74c3c; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do
            late_today
          end
          span "Late Today"
        end
      end
    end

    # === Monthly Stats ===
    panel "This Month’s Stats" do
      div style: "display: flex; gap: 30px; justify-content: space-evenly; margin: 20px 0;" do
        div style: "background:#2ecc71; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do
            on_time_month
          end
          span "On Time (This Month)"
        end

        div style: "background:#e74c3c; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do
            late_month
          end
          span "Late (This Month)"
        end
      end
    end

    # === Users with More than 3 Lates This Month ===
    late_users = User.joins(:time_clocks)
                     .where(time_clocks: { status: "late", clock_in: month_range })
                     .group("users.id")
                     .having("COUNT(time_clocks.id) > 3")
                     .select("users.*, COUNT(time_clocks.id) as late_count")

    if late_users.any?
      panel "Users with More than 3 Lates (This Month)" do
        table_for late_users do
          column "User" do |user|
            link_to user.email, admin_user_path(user)
          end
          column "Late Count", :late_count
        end
      end
    else
      panel "Users with More than 3 Lates (This Month)" do
        div style: "padding: 15px; text-align:center; color: #555;" do
          "🎉 No users with more than 3 lates this month!"
        end
      end
    end

    # === Users with 2+ Leaves This Month ===
    working_days = (Time.zone.today.beginning_of_month..Time.zone.today.end_of_month).select { |d| (1..5).include?(d.wday) }

    leave_users = User.all.map do |user|
      clock_in_days = user.time_clocks.where(clock_in: month_range).pluck(:clock_in).map(&:to_date).uniq
      leave_count = working_days.count - clock_in_days.count
      [user, leave_count]
    end.select { |_user, count| count >= 2 }

    if leave_users.any?
      panel "Users with 2+ Leaves (This Month)" do
        table_for leave_users do
          column "User" do |user, _count|
            link_to user.email, admin_user_path(user)
          end
          column "Leave Count" do |_user, count|
            count
          end
        end
      end
    else
      panel "Users with 2+ Leaves (This Month)" do
        div style: "padding: 15px; text-align:center; color: #555;" do
          "🎉 No users with 2 or more leaves this month!"
        end
      end
    end
  end
end

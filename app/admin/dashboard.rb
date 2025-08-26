ActiveAdmin.register_page "Dashboard" do
  
  content do
    div do
      raw "<script src='https://cdn.jsdelivr.net/npm/chart.js'></script>"
    end
    today_range = Time.zone.now.beginning_of_day..Time.zone.now.end_of_day
    month_range = Time.zone.now.beginning_of_month..Time.zone.now.end_of_month

    total_users   = User.count
    on_time_today = TimeClock.where(status: 'on_time', clock_in: today_range).count
    late_today    = TimeClock.where(status: 'late', clock_in: today_range).count
    on_time_month = TimeClock.where(status: 'on_time', clock_in: month_range).count
    late_month    = TimeClock.where(status: 'late', clock_in: month_range).count

    # =========================
    # Today’s Stats Panel
    # =========================
    panel "Today’s Stats" do
      div style: "display: flex; gap: 30px; justify-content: space-around; margin: 20px 0;" do
        div style: "background:#3498db; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do total_users end
          span "Total Users"
        end
        div style: "background:#2ecc71; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do on_time_today end
          span "On Time Today"
        end
        div style: "background:#e74c3c; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do late_today end
          span "Late Today"
        end
      end

      # Pie chart for today
      div style: "width: 300px; height: 300px; margin: auto;" do
        "<canvas id='todayChart' width='200' height='200'></canvas>".html_safe
      end

      today_chart_data = {
        labels: ["On Time", "Late", "Not Clocked In"],
        datasets: [{
          data: [on_time_today, late_today, total_users - (on_time_today + late_today)],
          backgroundColor: ["#2ecc71", "#e74c3c", "#95a5a6"]
        }]
      }.to_json

      script do
        raw <<-JS
          document.addEventListener("DOMContentLoaded", function() {
            var ctx = document.getElementById('todayChart').getContext('2d');
            new Chart(ctx, {
              type: 'pie',
              data: #{today_chart_data},
              options: {
                responsive: true,
                plugins: { legend: { position: 'bottom' } }
              }
            });
          });
        JS
      end
    end

    # =========================
    # Monthly Stats Panel
    # =========================
    panel "This Month’s Stats" do
      div style: "display: flex; gap: 30px; justify-content: space-evenly; margin: 20px 0;" do
        div style: "background:#2ecc71; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do on_time_month end
          span "On Time (This Month)"
        end
        div style: "background:#e74c3c; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          h2 style: "font-size:36px; margin-bottom:8px;" do late_month end
          span "Late (This Month)"
        end
      end

      # Pie chart for month
      div style: "width: 300px; height: 300px; margin: auto;" do
        "<canvas id='monthChart' width='400' height='400'></canvas>".html_safe
      end

      month_chart_data = {
        labels: ["On Time", "Late", "Not Clocked In"],
        datasets: [{
          data: [on_time_month, late_month, total_users - (on_time_month + late_month)],
          backgroundColor: ["#2ecc71", "#e74c3c", "#95a5a6"]
        }]
      }.to_json

      script do
        raw <<-JS
          document.addEventListener("DOMContentLoaded", function() {
            var ctx = document.getElementById('monthChart').getContext('2d');
            new Chart(ctx, {
              type: 'pie',
              data: #{month_chart_data},
              options: {
                responsive: true,
                plugins: { legend: { position: 'bottom' } }
              }
            });
          });
        JS
      end
    end

    # =========================
    # Users with More than 3 Lates
    # =========================
    late_users = User.joins(:time_clocks)
                     .where(time_clocks: { status: "late", clock_in: month_range })
                     .group("users.id")
                     .having("COUNT(time_clocks.id) > 3")
                     .select("users.*, COUNT(time_clocks.id) as late_count")

    panel "Users with More than 3 Lates (This Month)" do
      if late_users.any?
        table_for late_users do
          column "User" do |user| link_to user.email, admin_user_path(user) end
          column "Late Count", :late_count
        end
      else
        div style: "padding: 15px; text-align:center; color: #555;" do
          "🎉 No users with more than 3 lates this month!"
        end
      end
    end

    # =========================
    # Users with 2+ Leaves
    # =========================
    working_days = (Time.zone.today.beginning_of_month..Time.zone.today.end_of_month).select { |d| (1..5).include?(d.wday) }

    leave_users = User.all.map do |user|
      clock_in_days = user.time_clocks.where(clock_in: month_range).pluck(:clock_in).map(&:to_date).uniq
      leave_count = working_days.count - clock_in_days.count
      [user, leave_count]
    end.select { |_user, count| count >= 2 }

    panel "Users with 2+ Leaves (This Month)" do
      if leave_users.any?
        table_for leave_users do
          column "User" do |user, _count| link_to user.email, admin_user_path(user) end
          column "Leave Count" do |_user, count| count end
        end
      else
        div style: "padding: 15px; text-align:center; color: #555;" do
          "🎉 No users with 2 or more leaves this month!"
        end
      end
    end

    # =========================
    # Live Current State of Users
    # =========================
    current_states = User.includes(:time_clocks).map do |user|
      last_clock = user.time_clocks.order(clock_in: :desc).first
      {
        user: user,
        state: last_clock&.current_state || "off"
      }
    end

    panel "Live Current State of Users" do
      table_for current_states do
        column "User" do |row| link_to row[:user].email, admin_user_path(row[:user]) end
        column "Current State" do |row|
          state = row[:state]
          status_tag(state.titleize,
            class: case state
                   when "working"  then "ok"
                   when "on_break" then "warning"
                   else "error"
                   end
          )
        end
      end
    end
  end
end

ActiveAdmin.register_page "Dashboard" do
  
  content do
     
    div do
      raw "<script src='https://cdn.jsdelivr.net/npm/chart.js'></script>"
    end
       now = Time.zone.now
    if now.hour < 3
      shift_start = (now - 1.day).change(hour: 17, min: 45, sec: 0)
      shift_end   = now.change(hour: 3, min: 0, sec: 0)
    else
      shift_start = now.change(hour: 17, min: 45, sec: 0)
      shift_end   = (now + 1.day).change(hour: 3, min: 0, sec: 0)
    end

    shift_range = shift_start..shift_end
    month_range = Time.zone.now.beginning_of_month..Time.zone.now.end_of_month

    total_users   = User.count
    on_time_today = TimeClock.where(status: 'on_time', clock_in: shift_range).count
    late_today    = TimeClock.where(status: 'late', clock_in: shift_range).count
    on_time_month = TimeClock.where(status: 'on_time', clock_in: month_range).count
    late_month    = TimeClock.where(status: 'late', clock_in: month_range).count

    # =========================
    # Live Current State Grouped by All Departments
    # =========================

    departments = User.distinct.pluck(:department).compact.sort
    current_states_by_department = {}

    departments.each do |dept|
      users = User.includes(time_clocks: :breaks).where(department: dept)

      states = users.map do |user|
        last_clock = user.time_clocks.where(clock_in: shift_range).order(clock_in: :desc).first

        state =
  if last_clock.nil?
    "off"
  elsif last_clock.breaks.where(break_out: nil).exists?
    last_break = last_clock.breaks.where(break_out: nil).last

    case last_break.break_type
    when "Meeting"
      "meeting"
    when "Downtime"
      "downtime"
    else
      "on_break"
    end

  elsif last_clock.clock_out.nil?
    "working"
  else
    "off"
  end


        { user: user, state: state }
      end

      current_states_by_department[dept] = states
    end

    panel "Live Current State of Users by Department", class: "height-class2" do
  if departments.empty?
    div style: "padding: 15px; text-align:center; color: #888;" do
      "No departments found."
    end
  else
    departments.each_slice(4) do |dept_pair|
      div style: "display: flex; gap: 30px; justify-content: space-between; margin-bottom: 30px;" do
        dept_pair.each do |dept|
          states = current_states_by_department[dept]

          div style: "flex: 1;" , class:'height-class3' do
            h3 "#{dept.upcase} Department (#{states.size} users)"
            table_for states do
              column "User" do |row|
                link_to row[:user].name, admin_user_path(row[:user])
              end
              column "Current State" do |row|
                state = row[:state]
                status_tag(state.titleize,
                  class: case state
                         when "working"  then "ok"
                         when "on_break" then "warning"
                         when "Meeting" then "warning"
                         else "error"
                         end
                )
              end
            end
          end
        end
      end
    end
  end
end

    # =========================
    # Today’s Stats Panel
    # =========================
    panel "Today’s Stats", class:"mt-4" do
      div style: "display: flex; gap: 30px; justify-content: space-around; margin: 20px 0 mt-4;" do
        div style: "background:#3498db; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
          raw <<-HTML
    <a href="/admin/users" style="text-decoration: none;">
      <div style="background:#3498db; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;">
        <h2 style="font-size:36px; margin-bottom:8px;">#{total_users}</h2>
        <span>Total Users</span>
      </div>
    </a>
  HTML
        end


        div style: "background:#2ecc71; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
        raw <<-HTML
    <a href="/admin/time_clocks?q[clock_in_gteq]=#{Date.today}&q[status_cont]=on_time&commit=Filter&order=id_desc" style="text-decoration: none;">
      <div style="background:#2ecc71; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;">
        <h2 style="font-size:36px; margin-bottom:8px;">#{on_time_today}</h2>
        <span>On Time Today</span>
      </div>
    </a>
  HTML
        end
        

         
        div style: "background:#e74c3c; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;" do
           raw <<-HTML
    <a href="/admin/time_clocks?q[clock_in_gteq]=#{Date.today}&q[status_cont]=late&commit=Filter&order=id_desc" style="text-decoration: none;">
      <div style="background:#e74c3c; color:white; padding:30px; border-radius:14px; flex:1; text-align:center;">
        <h2 style="font-size:36px; margin-bottom:8px;">#{late_today}</h2>
        <span>Late Today</span>
      </div>
    </a>
  HTML
        end
      end

      # Pie chart for today
      div style: "width: 300px; height: 300px; margin: auto; margin-top: 20px" do
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
month_range = Time.zone.today.beginning_of_month.beginning_of_day..Time.zone.today.end_of_day
# Get all working days (Mon–Fri) within this range
working_days = (Time.zone.today.beginning_of_month..Time.zone.today.end_of_day).select { |d| (1..5).include?(d.wday) }
# Calculate leave counts for each user
leave_users = User.all.map do |user|
  # Get all unique clock-in dates for the user within this range
  clock_in_days = user.time_clocks.where(clock_in: month_range).pluck(:clock_in).map(&:to_date).uniq
  # Calculate leave count
  leave_count = working_days.count - clock_in_days.count

  [user, leave_count]
end.select { |_user, count| count > 2 } 
    panel "Users with 2+ Leaves (This Month)", class: "height-class" do
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

  end
end

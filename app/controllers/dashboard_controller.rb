class DashboardController < ApplicationController
  before_action :authenticate_user!
  # Page permissions from Settings -> Roles & Permissions. Viewing a specific
  # person's timesheet additionally requires managing them (checked per action).
  before_action -> { authorize_page!("executive_timesheets") },
                only: %i[timesheet_record executive_timesheets]
  include DashboardHelper

  def index
    @time_clock = current_user.time_clocks.last

    monday = Date.today.beginning_of_week(:monday)
    friday = monday + 4.days

    @time_clocks = current_user.time_clocks
      .where(clock_in: monday.beginning_of_day..friday.end_of_day)
      .order(clock_in: :desc)
    @time_clocks_current_month = current_user.time_clocks
      .where(clock_in: Time.current.beginning_of_month..Time.current.end_of_month)
      .order(clock_in: :desc)

    @today_half_day_leave = current_user.leaves.where(leave_type: :half_day, start_date: Date.current).last
    load_monthly_dept_stats if can_view?("department_stats") && current_user.direct_reports.any?
  end

  def manager_status
    return head :forbidden unless can_view?("manager_status")

    render partial: 'dashboard/manager_executives_status', layout: false
  end

  def team_status
    authorize_page!("team_status")
  end

  def timesheet_record
    @employee = User.find(params[:id])
    unless current_user.manages?(@employee)
      redirect_to root_path, alert: "Not authorized."
      return
    end
    @time_clock = @employee.time_clocks.includes(:breaks).find(params[:tc_id])
    @current_month = @time_clock.clock_in.to_date
  end

  def executive_timesheets
    @employee = User.find(params[:id])

    unless current_user.manages?(@employee)
      redirect_to root_path, alert: "Not authorized to view this executive."
      return
    end

    @current_month = params[:month] ? Date.parse(params[:month]) : Date.current
    @time_clocks = @employee.time_clocks
      .includes(:breaks)
      .where(clock_in: @current_month.beginning_of_month.beginning_of_day..@current_month.end_of_month.end_of_day)
      .order(:clock_in)
    render 'dashboard/executive_timesheets'
  end

  private

  def load_monthly_dept_stats
    # Your team is everyone below you in the organogram, whatever department
    # they sit in - no hardcoded department list needed.
    exec_users = User.employed.where(id: current_user.subordinate_ids).to_a
    @target_departments = exec_users.map { |u| u[:department] }.compact.uniq.sort
    exec_ids = exec_users.map(&:id)

    twelve_months_ago = 12.months.ago.beginning_of_month
    all_tcs = TimeClock.includes(:breaks)
      .where(user_id: exec_ids)
      .where('clock_in >= ?', twelve_months_ago)
      .to_a

    @monthly_dept_stats = {}
    @dept_summary       = {}

    @target_departments.each do |dept|
      dept_exec_ids = exec_users.select { |u| u.department == dept }.map(&:id)
      dept_tcs = all_tcs.select { |tc| dept_exec_ids.include?(tc.user_id) }

      total_clock_ins = dept_tcs.count
      total_lates     = dept_tcs.count { |tc| tc.status == "late" }
      total_on_time   = total_clock_ins - total_lates

      late_by_user = dept_tcs.select { |tc| tc.status == "late" }
                              .group_by(&:user_id)
                              .transform_values(&:count)
      most_late_uid   = late_by_user.max_by { |_, n| n }&.first
      most_late_user  = exec_users.find { |u| u.id == most_late_uid }
      most_late_count = late_by_user[most_late_uid].to_i

      @dept_summary[dept] = {
        total_clock_ins: total_clock_ins,
        total_lates:     total_lates,
        total_on_time:   total_on_time,
        most_late_user:  most_late_user,
        most_late_count: most_late_count
      }

      @monthly_dept_stats[dept] = dept_tcs
        .group_by { |tc| tc.clock_in.beginning_of_month }
        .map do |month, month_tcs|
          half_days = month_tcs.count do |tc|
            next false unless tc.clock_out.present?
            non_mtg_break_secs = tc.breaks
              .reject { |b| b.break_type == "Meeting" }
              .sum { |b| b.break_out.present? ? (b.break_out - b.break_in).to_i : 0 }
            (tc.clock_out - tc.clock_in).to_i - non_mtg_break_secs < 16200
          end
          month_lates = month_tcs.count { |tc| tc.status == "late" }
          {
            month:      month,
            clock_ins:  month_tcs.count,
            lates:      month_lates,
            half_days:  half_days,
            on_time:    month_tcs.count - month_lates
          }
        end.sort_by { |m| m[:month] }.reverse
    end
  end
end
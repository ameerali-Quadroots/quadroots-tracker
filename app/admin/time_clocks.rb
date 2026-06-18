ActiveAdmin.register TimeClock do

controller do
  def scoped_collection
    # Eager-load employee + breaks to avoid N+1 queries on the index/export.
    # references(:employee) keeps the users.* WHERE filters below working.
    scope = super.includes(:employee, :breaks).references(:employee)

    # Filter by nested employee
    scope = scope.where(user_id: params[:employee_id]) if params[:employee_id].present?

    if current_admin_user.super_admin? || current_admin_user.qa_admin?
      scope
    elsif current_admin_user.department&.upcase == "HOD'S"
      scope.where(users: { department: %w[WEB SEO ADS CONTENT] })
    else
      scope.where(users: { department: current_admin_user.department })
    end
  end

  # Employees this admin is allowed to see, used for the "did not clock in" report.
  def permitted_employees
    scope = User.employed
    scope =
      if current_admin_user.super_admin? || current_admin_user.qa_admin?
        scope
      elsif current_admin_user.department&.upcase == "HOD'S"
        scope.where(department: %w[WEB SEO ADS CONTENT])
      else
        scope.where(department: current_admin_user.department)
      end
    scope.order(:department, :name)
  end

  # Convert a named period into a clock_in datetime range.
  def period_range(period)
    today = Time.zone.today
    case period.to_s
    when "today"     then today.beginning_of_day..today.end_of_day
    when "week"      then today.beginning_of_week..today.end_of_week.end_of_day
    when "month"     then today.beginning_of_month..today.end_of_month.end_of_day
    when "quarter"   then today.beginning_of_quarter..today.end_of_quarter.end_of_day
    when "half_year"
      if today.month <= 6
        Date.new(today.year, 1, 1).beginning_of_day..Date.new(today.year, 6, 30).end_of_day
      else
        Date.new(today.year, 7, 1).beginning_of_day..Date.new(today.year, 12, 31).end_of_day
      end
    end
  end

  # Records to export: a named period if given, otherwise the active filters.
  def export_scope
    base = scoped_collection.includes(:breaks)
    if params[:period].present?
      range = period_range(params[:period])
      range ? base.where(clock_in: range) : base
    else
      base.ransack(params[:q]).result
    end
  end
end

  belongs_to :user, optional: true

  permit_params :employee_id, :clock_in, :clock_out, :total_duration, :status, :break_duration, :current_state,
                breaks_attributes: [:id, :break_in, :break_out, :_destroy]

  actions :all, except: [:new, :create]

  # Filters
  filter :employee_name_cont, as: :string, label: 'Employee Name'
  filter :employee_email, as: :string
  filter :employee_department_in,
         as: :select,
         label: "Departments",
         multiple: true,
         input_html: { class: 'select2-filter' },
         collection: -> {
           if current_admin_user.super_admin? || current_admin_user.qa_admin?
             TimeClock.joins(:employee).distinct.pluck('users.department').compact.uniq.sort
           elsif current_admin_user.department&.upcase == "HOD'S"
             %w[WEB SEO ADS CONTENT]
           else
             [current_admin_user.department]
           end
         }

  filter :clock_in
  filter :clock_out
  filter :status, as: :select, collection: -> { TimeClock.distinct.pluck(:status).compact }
  filter :current_state, as: :select, collection: -> { TimeClock.distinct.pluck(:current_state).compact }

  # Export as XLSX (with a per-break-type breakdown and late minutes)
  collection_action :export_xlsx do
    require 'caxlsx'

    timeclocks = export_scope

    package  = Axlsx::Package.new
    workbook = package.workbook

    break_types = Break::VALID_BREAK_TYPES

    workbook.add_worksheet(name: "Timeclocks") do |sheet|
      header = ["Date", "User", "Department", "IP Address", "Clock In", "Clock Out", "Late (min)"]
      header += break_types
      header += ["Total Break", "Working Duration", "Status"]
      sheet.add_row header

      timeclocks.find_each do |tc|
        by_type = tc.break_seconds_by_type

        row = [
          tc.clock_in&.strftime("%d-%m-%Y"),
          tc.employee&.name,
          tc.employee&.department,
          tc.ip_address,
          tc.clock_in&.strftime("%I:%M %p"),
          tc.clock_out&.strftime("%I:%M %p"),
          tc.late_minutes
        ]
        row += break_types.map { |type| tc.formatted_duration(by_type[type]) }
        row += [
          tc.formatted_break_duration,
          tc.formatted_duration(tc.total_duration),
          tc.status
        ]
        sheet.add_row row
      end
    end

    label = params[:period].presence || "filtered"
    send_data package.to_stream.read,
              filename: "timeclocks_#{label}_#{Time.zone.today}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  # Today's timesheet: includes employees who did NOT clock in, plus late minutes
  collection_action :today_timesheet do
    require 'caxlsx'

    ref       = Time.current
    shift_day = ref.hour < 12 ? ref.to_date - 1 : ref.to_date
    window    = shift_day.beginning_of_day.change(hour: 12)..(shift_day + 1).beginning_of_day.change(hour: 12)

    timeclocks = scoped_collection.includes(:breaks).where(clock_in: window).index_by(&:user_id)

    package  = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Today Timesheet") do |sheet|
      sheet.add_row ["Employee", "Department", "Shift Time", "Status", "Clock In", "Late (min)", "Clock Out", "Working Duration", "Total Break"]

      permitted_employees.each do |emp|
        tc = timeclocks[emp.id]
        shift = emp.shift_time&.strftime("%I:%M %p")

        if tc
          sheet.add_row [
            emp.name,
            emp.department,
            shift,
            tc.status,
            tc.clock_in&.strftime("%I:%M %p"),
            tc.late_minutes,
            tc.clock_out&.strftime("%I:%M %p"),
            tc.formatted_duration(tc.total_duration),
            tc.formatted_break_duration
          ]
        else
          sheet.add_row [emp.name, emp.department, shift, "Did not clock in", nil, nil, nil, nil, nil]
        end
      end
    end

    send_data package.to_stream.read,
              filename: "today_timesheet_#{shift_day}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  # Today's late arrivals + employees who did not clock in (no break columns)
  collection_action :today_late_absent do
    require 'caxlsx'

    ref       = Time.current
    shift_day = ref.hour < 12 ? ref.to_date - 1 : ref.to_date
    window    = shift_day.beginning_of_day.change(hour: 12)..(shift_day + 1).beginning_of_day.change(hour: 12)

    timeclocks = scoped_collection.where(clock_in: window).index_by(&:user_id)

    package  = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Late & Absent") do |sheet|
      sheet.add_row ["Employee", "Department", "Shift Time", "Status", "Clock In", "Late (min)"]

      permitted_employees.each do |emp|
        tc    = timeclocks[emp.id]
        shift = emp.shift_time&.strftime("%I:%M %p")

        if tc.nil?
          sheet.add_row [emp.name, emp.department, shift, "Did not clock in", nil, nil]
        elsif tc.status == "late"
          sheet.add_row [
            emp.name,
            emp.department,
            shift,
            "Late",
            tc.clock_in&.strftime("%I:%M %p"),
            tc.late_minutes
          ]
        end
        # On-time employees are intentionally skipped from this report
      end
    end

    send_data package.to_stream.read,
              filename: "today_late_absent_#{shift_day}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  action_item :exports, only: :index do
    dropdown_menu "Export" do
      item "Today",         url_for(action: :export_xlsx, period: "today")
      item "This Week",     url_for(action: :export_xlsx, period: "week")
      item "This Month",    url_for(action: :export_xlsx, period: "month")
      item "This Quarter",  url_for(action: :export_xlsx, period: "quarter")
      item "Half Year",     url_for(action: :export_xlsx, period: "half_year")
      item "Current Filter", url_for(params.permit!.to_h.merge(action: :export_xlsx))
      item "Today Timesheet (incl. absentees)", url_for(action: :today_timesheet)
      item "Today's Late & Absent (no breaks)", url_for(action: :today_late_absent)
    end
  end

  # Index Page
  index do
    selectable_column
    column "User", sortable: 'users.name' do |tc|
      tc.employee&.name
    end
    column "Department" do |tc|
      tc.employee&.department&.upcase || "N/A"
    end
    column :current_state do |tc|
      case tc.current_state
      when "on_break"
        span "On Break", style: "background-color: #ffff00; color: black; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      when "working"
        span "Working", style: "background-color: #2ecc71; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      else
        span tc.current_state || "N/A", style: "background-color: #bdc3c7; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      end
    end
    column :clock_in
    column :clock_out

    column "Live Working Duration" do |tc|
      if tc.clock_out.present?
        tc.formatted_duration(tc.total_duration)
      else
        duration = tc.live_working_duration
        content_tag(:span,
          tc.formatted_duration(duration),
          class: "live-duration",
          data: {
            clock_in: tc.clock_in.to_i,
            breaks: tc.breaks.map { |b| { in: b.break_in&.to_i, out: b.break_out&.to_i || 0 } }.to_json,
            id: tc.id
          }
        )
      end
    end

    column "Total Duration" do |tc|
      tc.formatted_duration(tc.total_duration)
    end

    column :status do |tc|
      case tc.status
      when "late"
        span "Late", style: "background-color: #e74c3c; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      when "on_time"
        span "On Time", style: "background-color: #2ecc71; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      else
        span tc.status || "N/A", style: "background-color: #bdc3c7; color: white; padding: 4px 8px; border-radius: 5px; font-weight: bold;"
      end
    end

    column "Breaks" do |tc|
      if tc.breaks.any?
        ul do
          tc.breaks.each do |br|
            li "#{br.break_in&.strftime('%H:%M:%S')} - #{br.break_out&.strftime('%H:%M:%S') || 'Ongoing'}"
          end
        end
      else
        status_tag("No Breaks", class: "status_tag warning")
      end
    end

    column "Break Duration" do |tc|
      tc.formatted_break_duration
    end

    column "Downtime Duration" do |tc|
      tc.calculate_downtime
    end

    # Duplicate IP logic
    shift_start = if Time.current.hour >= 17
                    Time.current.change(hour: 17, min: 45)
                  else
                    (Time.current - 1.day).change(hour: 17, min: 45)
                  end
    shift_end = shift_start + 9.hours + 15.minutes

    duplicate_ips_in_shift = TimeClock.where(clock_in: shift_start..shift_end).group(:ip_address).having('count(*) > 1').pluck(:ip_address)

    column :ip_address do |tc|
      ip = tc.ip_address
      clock_in = tc.clock_in
      in_shift = clock_in.between?(shift_start, shift_end)
      color =
        if duplicate_ips_in_shift.include?(ip) && in_shift
          'red'
        elsif in_shift
          'green'
        else
          'black'
        end
      status_tag ip, style: "color: #{color}; font-weight: bold;", class: "text-primary"
    end

    actions
  end

  # Show Page
  show do
    render partial: "admin/time_clocks/show", locals: { time_clock: time_clock }
  end

  # Edit Page
  form do |f|
    f.semantic_errors

    f.inputs "TimeClock Details" do
      f.input :employee
      f.input :clock_in, as: :datetime_picker
      f.input :clock_out, as: :datetime_picker
      f.input :status
      f.input :current_state
      f.input :total_duration
    end

    f.inputs "Breaks" do
      f.has_many :breaks, allow_destroy: true, new_record: true do |b|
        b.input :break_in, as: :datetime_picker
        b.input :break_out, as: :datetime_picker
      end
    end

    f.actions
  end
end

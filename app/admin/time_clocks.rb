ActiveAdmin.register TimeClock do

 controller do
  def scoped_collection
    scope = super.joins(:employee)

    if current_admin_user.super_admin? || current_admin_user.qa_admin?
      scope
    elsif current_admin_user.department&.upcase == "HOD'S"
      scope.where(users: { department: %w[WEB SEO ADS CONTENT] })
    else
      scope.where(users: { department: current_admin_user.department })
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

  # Export as XLSX
  collection_action :export_xlsx do
    require 'caxlsx'

    ransack_query = TimeClock.ransack(params[:q])
    timeclocks = ransack_query.result.includes(:user)

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Timeclocks") do |sheet|
      sheet.add_row ["Date", "User", "Department", "IP Address", "Clock In", "Clock Out", "Break Duration", "Total Duration", "Status"]
      timeclocks.find_each do |tc|
        sheet.add_row [
          tc.clock_in&.strftime("%d-%m-%Y"),
          tc.employee&.name,
          tc.employee&.department,
          tc.ip_address,
          tc.clock_in&.strftime("%I:%M %p"),
          tc.clock_out&.strftime("%I:%M %p"),
          tc.formatted_break_duration,
          tc.formatted_duration(tc.total_duration),
          tc.status
        ]
      end
    end

    send_data package.to_stream.read,
              filename: "timeclocks_#{Time.zone.today}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  action_item :export_xlsx, only: :index do
    link_to 'Export XLSX', url_for(params.permit!.to_h.merge(action: :export_xlsx)), method: :get
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
    attributes_table do
      row :user
      row("Department") { time_clock.employee&.department || "N/A" }
      row :clock_in
      row :clock_out
      row :status
      row :current_state
      row("Total Duration") { time_clock.formatted_duration(time_clock.total_duration) }
      row("Break Duration") { time_clock.formatted_break_duration }
      row :ip_address
    end

    panel "Breaks Details" do
      if time_clock.breaks.any?
        table_for time_clock.breaks do
          column("Break In") { |br| br.break_in&.strftime('%Y-%m-%d %H:%M:%S') }
          column("Break Out") { |br| br.break_out&.strftime('%Y-%m-%d %H:%M:%S') || "Ongoing" }
          column("Break Duration") do |br|
            if br.break_in && br.break_out
              time_clock.formatted_duration(br.break_out - br.break_in)
            else
              "Ongoing"
            end
          end
        end
      else
        div do
          status_tag("No Breaks", class: "status_tag warning")
        end
      end
    end
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

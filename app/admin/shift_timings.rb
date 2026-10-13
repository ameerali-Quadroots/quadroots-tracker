# Change the shift start time for many employees at once: everyone, or whole
# departments. Meant for seasonal moves (6 PM in summer, 8 PM in winter); one-off
# exceptions are still set on the employee's own edit screen afterwards.
ActiveAdmin.register_page "Shift Timings" do
  menu parent: "Settings", label: "Shift Timings", priority: 5

  controller do
    helper_method :shift_timing_departments, :shift_timing_all_allowed?, :shift_timing_rows, :shift_timing_all_count

    private

    # Only super/QA admins may change the whole company in one go.
    def shift_timing_all_allowed?
      current_admin_user.super_admin? || current_admin_user.qa_admin?
    end

    # Departments this admin may change; same scoping as Time Clocks and KPI.
    def shift_timing_departments
      @shift_timing_departments ||= begin
        departments = Department.order(:position, :name)
        shift_timing_all_allowed? ? departments.to_a : departments.where(name: current_admin_user.viewable_department_names).to_a
      end
    end

    # One row per department: head count and how many employees are on each
    # shift time, most common first.
    def shift_timing_rows
      @shift_timing_rows ||= begin
        by_department = User.employed.where(department_id: shift_timing_departments.map(&:id))
                            .pluck(:department_id, :shift_time).group_by(&:first)

        shift_timing_departments.map do |department|
          times = by_department.fetch(department.id, []).map(&:last)
          { department: department, total: times.size,
            timings: times.tally.sort_by { |time, count| [-count, time ? time.seconds_since_midnight : -1] } }
        end
      end
    end

    def shift_timing_all_count
      User.employed.count
    end
  end

  content title: "Shift Timings" do
    render partial: "admin/shift_timings/page",
           locals: { departments: shift_timing_departments, rows: shift_timing_rows,
                     all_allowed: shift_timing_all_allowed?,
                     all_count: (shift_timing_all_count if shift_timing_all_allowed?) }
  end

  page_action :apply, method: :post do
    departments =
      if params[:scope] == "all"
        next redirect_to(admin_shift_timings_path, alert: "Only a super admin can change all employees at once.") unless shift_timing_all_allowed?

        nil
      else
        # Anything outside this admin's departments is dropped, not trusted.
        chosen = Array(params[:department_ids]).map(&:to_i)
        shift_timing_departments.select { |department| chosen.include?(department.id) }
      end

    update = ShiftTimings::BulkUpdate.new(shift_time: params[:shift_time], departments: departments)
    result = update.call

    if result.success?
      who = departments.nil? ? "all employees" : departments.map(&:name).to_sentence
      redirect_to admin_shift_timings_path,
                  notice: "Shift start set to #{update.shift_time.strftime('%I:%M %p')} for " \
                          "#{helpers.pluralize(result.updated, 'employee')} (#{who})."
    else
      redirect_to admin_shift_timings_path, alert: result.error
    end
  end
end

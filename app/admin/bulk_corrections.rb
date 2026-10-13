# Remove the late mark from many employees for one shift day without edit
# requests - for days the server or the internet was down. Only the status
# changes; clock-in times stay as recorded. Every run is logged (BulkCorrection)
# and can be undone from this page.
ActiveAdmin.register_page "Bulk Correction" do
  menu label: "Bulk Correction", priority: 3

  controller do
    helper_method :correction_departments, :correction_all_allowed?, :correction_everyone?, :correction_date,
                  :correction_chosen_departments, :correction_before, :correction_preview, :correction_history, :correction_undoable?

    private

    # Only super/QA admins may correct the whole company in one go.
    def correction_all_allowed?
      current_admin_user.super_admin? || current_admin_user.qa_admin?
    end

    # Departments this admin may correct; same scoping as Time Clocks and KPI.
    def correction_departments
      @correction_departments ||= begin
        departments = Department.order(:position, :name)
        correction_all_allowed? ? departments.to_a : departments.where(name: current_admin_user.viewable_department_names).to_a
      end
    end

    # The shift day being corrected, from ?date=YYYY-MM-DD. Defaults to the
    # shift running now (still yesterday's date in the early hours); a future
    # date falls back to it too.
    def correction_date
      @correction_date ||= begin
        today = TimeClock.shift_date_at(Time.zone.now, nil)
        date = Date.iso8601(params[:date].to_s)
        date > today ? today : date
      rescue ArgumentError
        TimeClock.shift_date_at(Time.zone.now, nil)
      end
    end

    def correction_everyone?
      params[:scope] == "all"
    end

    # Ticked departments, limited to the ones this admin may correct.
    def correction_chosen_departments
      chosen = Array(params[:department_ids]).map(&:to_i)
      correction_departments.select { |department| chosen.include?(department.id) }
    end

    # The "clocked in before" time of day (HH:MM) from ?before=, or nil.
    def correction_before
      before = params[:before].to_s.strip
      TimeClocks::BulkCorrection.cutoff_on(correction_date, before) ? before : nil
    end

    # The correction for the current filter, or nil until a scope is chosen
    # (or when a department admin asks for everyone).
    def correction_preview
      return @correction_preview if defined?(@correction_preview)

      @correction_preview =
        if correction_everyone?
          TimeClocks::BulkCorrection.new(shift_date: correction_date, departments: nil,
                                         clocked_in_before: correction_before) if correction_all_allowed?
        elsif correction_chosen_departments.any?
          TimeClocks::BulkCorrection.new(shift_date: correction_date, departments: correction_chosen_departments,
                                         clocked_in_before: correction_before)
        end
    end

    # Super/QA admins see every recent correction, everyone else their own.
    def correction_history
      @correction_history ||= begin
        log = BulkCorrection.recent.includes(:admin_user, :undone_by).limit(20)
        correction_all_allowed? ? log : log.where(admin_user: current_admin_user)
      end
    end

    def correction_undoable?(correction)
      !correction.undone? && (correction_all_allowed? || correction.admin_user_id == current_admin_user.id)
    end
  end

  content title: "Bulk Correction" do
    render partial: "admin/bulk_corrections/page",
           locals: { departments: correction_departments, all_allowed: correction_all_allowed?,
                     everyone: correction_everyone? && correction_all_allowed?,
                     chosen_ids: correction_chosen_departments.map(&:id), date: correction_date,
                     before: correction_before,
                     preview: correction_preview, history: correction_history }
  end

  page_action :apply, method: :post do
    back = admin_bulk_correction_path(date: correction_date.iso8601, scope: params[:scope],
                                      department_ids: correction_chosen_departments.map(&:id), before: correction_before)

    if correction_everyone? && !correction_all_allowed?
      next redirect_to(admin_bulk_correction_path, alert: "Only a super admin can correct all employees at once.")
    end
    next redirect_to(back, alert: "Choose at least one of your departments.") if correction_preview.nil?

    result = correction_preview.apply(time_clock_ids: params[:time_clock_ids], reason: params[:reason],
                                      admin: current_admin_user)

    if result.success?
      redirect_to back, notice: "Late mark removed for #{helpers.pluralize(result.corrected, 'employee')} on " \
                                "#{correction_date.strftime('%d %b %Y')}."
    else
      redirect_to back, alert: result.error
    end
  end

  page_action :undo, method: :post do
    correction = BulkCorrection.find_by(id: params[:id])

    if correction.nil? || !correction_undoable?(correction)
      redirect_to admin_bulk_correction_path, alert: "That correction cannot be undone."
    elsif correction.undo!(admin: current_admin_user)
      redirect_to admin_bulk_correction_path,
                  notice: "Correction for #{correction.shift_date.strftime('%d %b %Y')} undone: " \
                          "#{helpers.pluralize(correction.time_clock_ids.size, 'employee')} back to late."
    else
      redirect_to admin_bulk_correction_path, alert: "That correction was already undone."
    end
  end
end

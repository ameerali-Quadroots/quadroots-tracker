module TimeClocks
  # Removes the late mark from many employees for one shift day, without edit
  # requests: for days the lateness was not their fault (server down, internet
  # outage). Only the status changes ("late" to "on_time"); clock-in times and
  # worked hours are left exactly as recorded. Employees with no record for the
  # day are not given one - see #missing_employees.
  #
  #   correction = TimeClocks::BulkCorrection.new(shift_date: Date.current, departments: [web])
  #   correction.late_clocks                      # who would be corrected
  #   correction.apply(time_clock_ids: ids, reason: "Server down", admin: current_admin_user)
  class BulkCorrection
    Result = Struct.new(:success, :corrected, :record, :error, keyword_init: true) do
      def success?
        success
      end
    end

    attr_reader :shift_date

    # departments: nil means every employee.
    def initialize(shift_date:, departments: nil)
      @shift_date = shift_date
      @departments = departments
    end

    # Late shifts of current employees in scope that belong to the day.
    def late_clocks
      @late_clocks ||= clocks_on_day.select { |tc| tc.status == "late" }
                                    .sort_by { |tc| tc.employee.name.to_s.strip.downcase }
    end

    # Current employees in scope with no time clock at all for the day.
    def missing_employees
      @missing_employees ||= begin
        present = clocks_on_day.map(&:user_id)
        employees.reject { |user| present.include?(user.id) }.sort_by { |user| user.name.to_s.strip.downcase }
      end
    end

    # Marks the given late shifts on time. Ids that are not late shifts of this
    # day and scope are dropped rather than trusted.
    def apply(time_clock_ids:, reason:, admin:)
      reason = reason.to_s.strip
      return failure("Give a reason for the correction.") if reason.blank?

      chosen = Array(time_clock_ids).map(&:to_i)
      ids = late_clocks.map(&:id) & chosen
      return failure("No late employees were selected.") if ids.empty?

      record = nil
      TimeClock.transaction do
        TimeClock.where(id: ids).update_all(status: "on_time", updated_at: Time.current)
        record = ::BulkCorrection.create!(admin_user: admin, shift_date: shift_date, reason: reason,
                                          scope_label: scope_label, time_clock_ids: ids)
      end

      Result.new(success: true, corrected: ids.size, record: record)
    end

    def scope_label
      @departments.nil? ? "All employees" : @departments.map(&:name).to_sentence
    end

    private

    def employees
      @employees ||= begin
        users = User.employed
        users = users.where(department_id: @departments.map(&:id)) unless @departments.nil?
        users.to_a
      end
    end

    def clocks_on_day
      @clocks_on_day ||= TimeClock.where(user_id: employees.map(&:id)).on_shift_dates(shift_date..shift_date)
    end

    def failure(message)
      Result.new(success: false, corrected: 0, error: message)
    end
  end
end

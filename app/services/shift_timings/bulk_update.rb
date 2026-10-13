module ShiftTimings
  # Sets the shift start time for many employees at once: everyone, or the
  # employees of the given departments. Used for seasonal changes (e.g. 6 PM in
  # summer, 8 PM in winter). Only current employees are touched, and past time
  # clocks are unaffected because each one stores its own shift start.
  #
  #   ShiftTimings::BulkUpdate.new(shift_time: "20:00").call                      # everyone
  #   ShiftTimings::BulkUpdate.new(shift_time: "20:00", departments: [web]).call  # one department
  class BulkUpdate
    Result = Struct.new(:success, :updated, :error, keyword_init: true) do
      def success?
        success
      end
    end

    TIME_FORMAT = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

    # departments: nil means every employee. An empty list is refused in #call
    # so a form submitted with nothing ticked cannot change the whole company.
    def initialize(shift_time:, departments: nil)
      @raw_time = shift_time.to_s.strip
      @departments = departments
    end

    def call
      return failure("Enter the shift start time as HH:MM.") if shift_time.nil?
      return failure("Choose at least one department.") if @departments && @departments.empty?

      updated = scope.update_all(shift_time: shift_time, updated_at: Time.current)
      Result.new(success: true, updated: updated)
    end

    # How many employees #call would change.
    def count
      scope.count
    end

    def shift_time
      return @shift_time if defined?(@shift_time)

      match = TIME_FORMAT.match(@raw_time)
      # Same form the employee edit screen stores: a time of day on 2000-01-01.
      @shift_time = match && Time.zone.local(2000, 1, 1, match[1].to_i, match[2].to_i)
    end

    private

    def scope
      users = User.employed
      @departments.nil? ? users : users.where(department_id: @departments.map(&:id))
    end

    def failure(message)
      Result.new(success: false, updated: 0, error: message)
    end
  end
end

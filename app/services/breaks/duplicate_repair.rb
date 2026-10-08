module Breaks
  # Cleans up after the bug that let someone already on a break start another
  # (the home page showed "Take Break" to people who were on a break, so every
  # click opened one more).
  #
  # Three repairs, on shifts clocked in since `since`:
  #   * an open shift with several open breaks keeps the first one running and
  #     drops the later ones - they were clicks made while already on a break,
  #     not breaks;
  #   * an open shift that says "working" while a break is open is put back on
  #     that break;
  #   * a finished shift whose overlapping breaks were added together when it
  #     clocked out gets its break time and hours worked recalculated.
  #
  # A shift whose breaks do not overlap is never touched, so totals corrected by
  # hand are safe. With dry_run nothing is written; the report is the same.
  class DuplicateRepair
    Report = Struct.new(:duplicates_removed, :states_corrected, :shifts_recalculated, :lines, keyword_init: true)

    def initialize(since:, dry_run: true)
      @since = since
      @dry_run = dry_run
      @report = Report.new(duplicates_removed: 0, states_corrected: 0, shifts_recalculated: 0, lines: [])
    end

    def call
      TimeClock.where(clock_in: @since..).includes(:breaks, :employee).find_each do |shift|
        shift.clock_out.blank? ? repair_open(shift) : repair_finished(shift)
      end
      @report
    end

    private

    def repair_open(shift)
      open = shift.open_breaks.sort_by { |b| [b.break_in, b.id] }
      return if open.empty?

      running, *extras = open
      if extras.any?
        note(shift, "#{extras.size} duplicate open break(s) removed, keeping the one started #{running.break_in.strftime('%H:%M:%S')}")
        @report.duplicates_removed += extras.size
        extras.each(&:destroy!) unless @dry_run
      end

      state = state_for(running.break_type)
      return if shift.current_state == state

      note(shift, "state #{shift.current_state.inspect} corrected to #{state.inspect}")
      @report.states_corrected += 1
      shift.update_columns(current_state: state) unless @dry_run
    end

    def repair_finished(shift)
      return unless overlapping?(shift)

      break_seconds = shift.total_break_seconds
      worked = [(shift.clock_out - shift.clock_in).to_i - break_seconds, 0].max
      return if shift.break_duration.to_i == break_seconds && shift.total_duration.to_i == worked

      note(shift, "break time #{minutes(shift.break_duration)} -> #{minutes(break_seconds)}, worked #{minutes(shift.total_duration)} -> #{minutes(worked)}")
      @report.shifts_recalculated += 1
      shift.update_columns(break_duration: break_seconds, total_duration: worked) unless @dry_run
    end

    # True when two completed non-meeting breaks cover the same time: adding
    # them up gives more than the time they actually span.
    def overlapping?(shift)
      summed = shift.breaks.sum do |b|
        next 0 if b.meeting? || b.break_in.blank? || b.break_out.blank?

        [(b.break_out - b.break_in).to_i, 0].max
      end
      summed > shift.total_break_seconds
    end

    def state_for(break_type)
      case break_type
      when "Meeting" then "Meeting"
      when "Downtime" then "Downtime"
      else "On break"
      end
    end

    def minutes(seconds)
      "#{(seconds.to_i / 60.0).round}m"
    end

    def note(shift, message)
      @report.lines << "shift ##{shift.id} #{shift.employee&.name.to_s.strip} (#{shift.clock_in.strftime('%d %b %H:%M')}): #{message}"
    end
  end
end

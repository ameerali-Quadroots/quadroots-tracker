require "test_helper"

class DuplicateBreakRepairTest < ActiveSupport::TestCase
  setup do
    @user = users(:exec_web_a)
    @start = Time.zone.local(2026, 9, 7, 18, 0)
  end

  def shift(open: true, state: "working")
    TimeClock.create!(employee: @user, status: "on_time", clock_in: @start, current_state: state,
                      clock_out: (open ? nil : @start + 8.hours))
  end

  def brk(tc, from:, to: nil, type: "Extra Break")
    Break.create!(time_clock: tc, break_type: type, break_in: @start + from, break_out: (to && @start + to))
  end

  def repair(dry_run: false)
    Breaks::DuplicateRepair.new(since: @start - 1.day, dry_run: dry_run).call
  end

  test "an open shift with several open breaks keeps only the first one running" do
    tc = shift
    first = brk(tc, from: 60.minutes)
    brk(tc, from: 61.minutes)
    brk(tc, from: 63.minutes)
    done = brk(tc, from: 10.minutes, to: 20.minutes)

    report = repair

    assert_equal [done, first].map(&:id).sort, tc.breaks.reload.map(&:id).sort
    assert_equal 2, report.duplicates_removed
    assert tc.reload.on_break?
  end

  test "an open shift left showing working while a break is open is put back on break" do
    tc = shift(state: "working")
    brk(tc, from: 60.minutes, type: "Meeting")

    repair

    assert_equal "Meeting", tc.reload.current_state
  end

  test "a finished shift whose overlapping breaks were added together has its hours put right" do
    tc = shift(open: false, state: "off")
    brk(tc, from: 60.minutes, to: 120.minutes)
    brk(tc, from: 61.minutes, to: 120.minutes)
    brk(tc, from: 62.minutes, to: 120.minutes)
    tc.update_columns(break_duration: 177.minutes.to_i, total_duration: (8.hours - 177.minutes).to_i)   # what the old sum stored

    report = repair

    assert_equal 60.minutes.to_i, tc.reload.break_duration
    assert_equal 7.hours.to_i, tc.total_duration
    assert_equal 1, report.shifts_recalculated
  end

  test "a shift with ordinary, separate breaks is left alone" do
    tc = shift(open: false, state: "off")
    brk(tc, from: 60.minutes, to: 70.minutes)
    brk(tc, from: 120.minutes, to: 130.minutes)
    tc.update_columns(break_duration: 1234, total_duration: 5678)   # e.g. corrected by hand through an edit request

    report = repair

    assert_equal [1234, 5678], [tc.reload.break_duration, tc.total_duration]
    assert_equal 0, report.shifts_recalculated
  end

  test "a dry run reports the same work but changes nothing" do
    tc = shift
    brk(tc, from: 60.minutes)
    brk(tc, from: 61.minutes)

    report = repair(dry_run: true)

    assert_equal 1, report.duplicates_removed
    assert_equal 2, tc.breaks.reload.count
  end

  test "shifts from before the cut-off are not touched" do
    tc = shift
    brk(tc, from: 60.minutes)
    brk(tc, from: 61.minutes)

    Breaks::DuplicateRepair.new(since: @start + 1.day, dry_run: false).call

    assert_equal 2, tc.breaks.reload.count
  end
end

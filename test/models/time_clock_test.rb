require "test_helper"

class TimeClockTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end

  # ---- Which day a shift belongs to -----------------------------------------
  # The shift runs from the evening into the early morning, so a clock-in after
  # midnight still belongs to the day the shift started on.

  test "an evening clock-in belongs to that day" do
    tc = TimeClock.new(employee: users(:exec_web_a), clock_in: Time.zone.local(2026, 9, 7, 18, 5))

    assert_equal Date.new(2026, 9, 7), tc.shift_date
  end

  test "a clock-in after midnight belongs to the previous day's shift" do
    tc = TimeClock.new(employee: users(:exec_web_a), clock_in: Time.zone.local(2026, 9, 8, 0, 20))

    assert_equal Date.new(2026, 9, 7), tc.shift_date
  end

  test "an early clock-in before the shift starts still belongs to that day" do
    tc = TimeClock.new(employee: users(:exec_web_a), clock_in: Time.zone.local(2026, 9, 7, 17, 40))

    assert_equal Date.new(2026, 9, 7), tc.shift_date
  end

  test "on_shift_dates finds a shift by the day it started, including a post-midnight clock-in" do
    user = users(:exec_web_a)
    evening = TimeClock.create!(employee: user, status: "on_time", clock_in: Time.zone.local(2026, 9, 7, 18, 0))
    after_midnight = TimeClock.create!(employee: user, status: "late", clock_in: Time.zone.local(2026, 9, 9, 0, 30))
    next_month = TimeClock.create!(employee: user, status: "late", clock_in: Time.zone.local(2026, 10, 1, 1, 0))

    found = TimeClock.where(user_id: user.id).on_shift_dates(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))

    assert_equal [evening, after_midnight, next_month].map(&:id).sort, found.map(&:id).sort
    assert_equal Date.new(2026, 9, 30), next_month.shift_date
  end

  test "on_shift_dates leaves out the early hours of the first day, which belong to the day before" do
    user = users(:exec_web_a)
    TimeClock.create!(employee: user, status: "late", clock_in: Time.zone.local(2026, 9, 1, 0, 45))

    assert_empty TimeClock.where(user_id: user.id).on_shift_dates(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))
  end

  # ---- Being on a break ------------------------------------------------------
  # Regression: "on a break" used to mean "the last break row is open". With the
  # breaks already loaded, "last" is whatever order the database returned, so an
  # open break could be missed, the page showed "Take Break" again, and every
  # extra click created another open break.

  def shift(clock_in: Time.zone.local(2026, 9, 7, 18, 0))
    TimeClock.create!(employee: users(:exec_web_a), status: "on_time", clock_in: clock_in, current_state: "working")
  end

  def brk(tc, from:, to: nil, type: "Extra Break")
    Break.create!(time_clock: tc, break_type: type, break_in: tc.clock_in + from, break_out: (to && tc.clock_in + to))
  end

  test "on a break whenever any break is open, not only when the newest row is" do
    tc = shift
    brk(tc, from: 2.hours)                       # still open
    brk(tc, from: 1.hour, to: 1.hour + 10.minutes) # created later, already closed

    assert tc.reload.on_break?
  end

  test "on a break is the same answer whether or not the breaks are already loaded" do
    tc = shift
    brk(tc, from: 2.hours)
    brk(tc, from: 1.hour, to: 1.hour + 10.minutes)

    fresh = TimeClock.find(tc.id)
    loaded = TimeClock.includes(:breaks).find(tc.id)
    loaded.breaks.to_a

    assert fresh.on_break?
    assert loaded.on_break?
  end

  test "not on a break once every break is closed" do
    tc = shift
    brk(tc, from: 1.hour, to: 1.hour + 10.minutes)

    assert_not tc.reload.on_break?
  end

  test "the current break is the open one" do
    tc = shift
    open = brk(tc, from: 2.hours)
    brk(tc, from: 1.hour, to: 1.hour + 10.minutes)

    assert_equal open, tc.reload.current_break
  end

  test "breaks come back in the order they were taken" do
    tc = shift
    later = brk(tc, from: 3.hours, to: 3.hours + 5.minutes)
    earlier = brk(tc, from: 1.hour, to: 1.hour + 5.minutes)

    assert_equal [earlier, later], tc.reload.breaks.to_a
    assert_equal later, tc.breaks.last
  end

  # ---- Break time ------------------------------------------------------------

  test "overlapping breaks are counted once, not added together" do
    tc = shift
    brk(tc, from: 60.minutes, to: 90.minutes)
    brk(tc, from: 70.minutes, to: 90.minutes)   # a duplicate started inside the first
    brk(tc, from: 75.minutes, to: 90.minutes)

    assert_equal 30.minutes.to_i, tc.reload.total_break_seconds
  end

  test "separate breaks are still added together" do
    tc = shift
    brk(tc, from: 60.minutes, to: 70.minutes)
    brk(tc, from: 120.minutes, to: 135.minutes)

    assert_equal 25.minutes.to_i, tc.reload.total_break_seconds
  end

  test "a meeting inside the shift is still not counted as break time" do
    tc = shift
    brk(tc, from: 60.minutes, to: 90.minutes, type: "Meeting")
    brk(tc, from: 120.minutes, to: 130.minutes)

    assert_equal 10.minutes.to_i, tc.reload.total_break_seconds
  end

  test "clocking out with duplicate open breaks does not take the break off the hours twice" do
    tc = shift
    brk(tc, from: 2.hours)
    brk(tc, from: 2.hours + 1.minute)
    brk(tc, from: 2.hours + 2.minutes)

    tc.reload.close_out!(at: tc.clock_in + 3.hours)

    assert_equal 1.hour.to_i, tc.break_duration
    assert_equal 2.hours.to_i, tc.total_duration
  end

  # --- shift start is fixed at clock-in ---

  test "the shift start is saved when the employee clocks in" do
    tc = shift(clock_in: Time.zone.local(2026, 9, 7, 18, 5))

    assert_equal Time.zone.local(2026, 9, 7, 18, 0), tc.reload.shift_start_at
  end

  test "changing the employee's shift time later does not move a past shift" do
    tc = shift(clock_in: Time.zone.local(2026, 9, 7, 18, 5))

    tc.employee.update!(shift_time: Time.zone.local(2000, 1, 1, 20, 0))
    tc = TimeClock.find(tc.id)

    assert_equal Time.zone.local(2026, 9, 7, 18, 0), tc.shift_start
    assert_equal Date.new(2026, 9, 7), tc.shift_date
    assert_equal 5, tc.late_minutes
  end

  test "a shift clocked in after the change uses the new shift time" do
    user = users(:exec_web_a)
    user.update!(shift_time: Time.zone.local(2000, 1, 1, 20, 0))

    tc = TimeClock.create!(employee: user, clock_in: Time.zone.local(2026, 12, 1, 20, 10))

    assert_equal Time.zone.local(2026, 12, 1, 20, 0), tc.shift_start
    assert_equal 10, tc.late_minutes
  end

  test "correcting the clock-in keeps the shift's own start time, not the employee's current one" do
    tc = shift(clock_in: Time.zone.local(2026, 9, 7, 18, 5))
    tc.employee.update!(shift_time: Time.zone.local(2000, 1, 1, 20, 0))
    tc = TimeClock.find(tc.id)

    tc.update!(clock_in: Time.zone.local(2026, 9, 8, 0, 30))

    assert_equal Time.zone.local(2026, 9, 7, 18, 0), tc.shift_start
  end

  test "a row saved without a stored shift start still works it out from the employee" do
    tc = shift(clock_in: Time.zone.local(2026, 9, 7, 18, 5))
    tc.update_columns(shift_start_at: nil)

    assert_equal Time.zone.local(2026, 9, 7, 18, 0), TimeClock.find(tc.id).shift_start
  end
end

require "test_helper"

class TimeClocks::BulkCorrectionTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 9, 7)

  setup do
    @admin = admin_users(:one)
    @late_a      = clock(:exec_web_a, 18, 40, "late")
    @late_b      = clock(:exec_web_b, 19, 5, "late")
    @on_time     = clock(:manager_web, 17, 58, "on_time")
    @late_design = clock(:exec_design, 18, 30, "late")
    # Late on another day: never part of this correction.
    @other_day   = TimeClock.create!(employee: users(:exec_web_a), status: "late",
                                     clock_in: Time.zone.local(2026, 9, 8, 18, 40))
  end

  def clock(user, hour, min, status)
    TimeClock.create!(employee: users(user), status: status, clock_in: Time.zone.local(2026, 9, 7, hour, min))
  end

  def correction(departments: [departments(:web)])
    TimeClocks::BulkCorrection.new(shift_date: DAY, departments: departments)
  end

  test "lists the late shifts of that day in the chosen departments" do
    assert_equal [@late_a, @late_b].map(&:id).sort, correction.late_clocks.map(&:id).sort
  end

  test "lists every department's late shifts when no departments are given" do
    assert_equal [@late_a, @late_b, @late_design].map(&:id).sort, correction(departments: nil).late_clocks.map(&:id).sort
  end

  test "a late clock-in after midnight belongs to the shift it was late for" do
    after_midnight = TimeClock.create!(employee: users(:manager_web), status: "late",
                                       clock_in: Time.zone.local(2026, 9, 7, 0, 30))

    assert_not_includes correction.late_clocks.map(&:id), after_midnight.id
    assert_includes TimeClocks::BulkCorrection.new(shift_date: DAY - 1, departments: [departments(:web)])
                                              .late_clocks.map(&:id), after_midnight.id
  end

  test "a clocked-in-before time keeps only the late shifts that came in earlier" do
    filtered = TimeClocks::BulkCorrection.new(shift_date: DAY, departments: [departments(:web)], clocked_in_before: "19:00")

    assert_equal [@late_a.id], filtered.late_clocks.map(&:id)
    assert_equal "Web, clocked in before 07:00 PM", filtered.scope_label
  end

  test "a morning clocked-in-before time falls after midnight" do
    after_midnight = TimeClock.create!(employee: users(:manager_web), status: "late",
                                       clock_in: Time.zone.local(2026, 9, 8, 0, 30))
    filtered = TimeClocks::BulkCorrection.new(shift_date: DAY, departments: [departments(:web)], clocked_in_before: "01:00")

    assert_equal [@late_a, @late_b, after_midnight].map(&:id).sort, filtered.late_clocks.map(&:id).sort
  end

  test "ids after the clocked-in-before time are not corrected" do
    filtered = TimeClocks::BulkCorrection.new(shift_date: DAY, departments: [departments(:web)], clocked_in_before: "19:00")
    result = filtered.apply(time_clock_ids: [@late_a.id, @late_b.id], reason: "Server down", admin: @admin)

    assert_equal 1, result.corrected
    assert_equal "late", @late_b.reload.status
  end

  test "an unreadable clocked-in-before time is ignored" do
    filtered = TimeClocks::BulkCorrection.new(shift_date: DAY, departments: [departments(:web)], clocked_in_before: "25:99")

    assert_nil filtered.clocked_in_before
    assert_equal [@late_a, @late_b].map(&:id).sort, filtered.late_clocks.map(&:id).sort
  end

  test "lists employees with no record for the day" do
    @late_b.destroy

    assert_equal [users(:exec_web_b)], correction.missing_employees
  end

  test "applying marks the chosen shifts on time and leaves the clock-in alone" do
    result = correction.apply(time_clock_ids: [@late_a.id, @late_b.id], reason: "Server down", admin: @admin)

    assert result.success?
    assert_equal 2, result.corrected
    assert_equal "on_time", @late_a.reload.status
    assert_equal Time.zone.local(2026, 9, 7, 18, 40), @late_a.clock_in
    assert_equal "late", @late_design.reload.status
    assert_equal "late", @other_day.reload.status
  end

  test "only the ticked shifts are corrected" do
    correction.apply(time_clock_ids: [@late_a.id], reason: "Server down", admin: @admin)

    assert_equal "on_time", @late_a.reload.status
    assert_equal "late", @late_b.reload.status
  end

  test "ids outside the day or the departments are ignored" do
    result = correction.apply(time_clock_ids: [@late_a.id, @late_design.id, @other_day.id, @on_time.id],
                              reason: "Server down", admin: @admin)

    assert_equal 1, result.corrected
    assert_equal "late", @late_design.reload.status
    assert_equal "late", @other_day.reload.status
  end

  test "applying keeps a record of who, why and which shifts" do
    result = correction.apply(time_clock_ids: [@late_a.id, @late_b.id], reason: "Server down", admin: @admin)

    log = result.record
    assert_equal @admin, log.admin_user
    assert_equal DAY, log.shift_date
    assert_equal "Server down", log.reason
    assert_equal "Web", log.scope_label
    assert_equal [@late_a.id, @late_b.id].sort, log.time_clock_ids.sort
    assert_not log.undone?
  end

  test "a reason is required" do
    result = correction.apply(time_clock_ids: [@late_a.id], reason: "  ", admin: @admin)

    assert_not result.success?
    assert_equal "late", @late_a.reload.status
    assert_equal 0, BulkCorrection.count
  end

  test "nothing to correct is refused, not logged" do
    result = correction.apply(time_clock_ids: [], reason: "Server down", admin: @admin)

    assert_not result.success?
    assert_equal 0, BulkCorrection.count
  end

  test "no edit requests are created" do
    assert_no_difference "EditRequest.count" do
      correction.apply(time_clock_ids: [@late_a.id], reason: "Server down", admin: @admin)
    end
  end

  test "undo puts the shifts back to late" do
    log = correction.apply(time_clock_ids: [@late_a.id, @late_b.id], reason: "Server down", admin: @admin).record

    assert log.undo!(admin: admin_users(:two))

    assert_equal "late", @late_a.reload.status
    assert_equal "late", @late_b.reload.status
    assert log.reload.undone?
    assert_equal admin_users(:two), log.undone_by
  end

  test "undo does not touch a shift that was on time before the correction" do
    log = correction.apply(time_clock_ids: [@late_a.id], reason: "Server down", admin: @admin).record

    log.undo!(admin: @admin)

    assert_equal "on_time", @on_time.reload.status
  end

  test "a correction can only be undone once" do
    log = correction.apply(time_clock_ids: [@late_a.id], reason: "Server down", admin: @admin).record
    log.undo!(admin: @admin)
    @late_a.update!(status: "on_time")

    assert_not log.undo!(admin: @admin)
    assert_equal "on_time", @late_a.reload.status
  end
end

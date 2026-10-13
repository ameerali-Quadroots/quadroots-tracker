require "test_helper"

class AutoClockJobTest < ActiveJob::TestCase
  setup do
    @eight     = users(:exec_web_a).tap { |u| u.update!(shift_time: Time.zone.local(2000, 1, 1, 20, 0)) }
    @half_past = users(:exec_web_b).tap { |u| u.update!(shift_time: Time.zone.local(2000, 1, 1, 20, 30)) }
    @eight_clock     = TimeClock.create!(employee: @eight, status: "on_time", current_state: "working",
                                         clock_in: Time.zone.local(2026, 9, 7, 19, 55))
    @half_past_clock = TimeClock.create!(employee: @half_past, status: "on_time", current_state: "working",
                                         clock_in: Time.zone.local(2026, 9, 7, 20, 25))
  end

  test "nobody is clocked out before their shift ends" do
    travel_to(Time.zone.local(2026, 9, 8, 4, 30)) { AutoClockJob.perform_now }

    assert_nil @eight_clock.reload.clock_out
    assert_nil @half_past_clock.reload.clock_out
  end

  test "each shift is closed at its own end time" do
    travel_to(Time.zone.local(2026, 9, 8, 5, 0)) { AutoClockJob.perform_now }

    assert_equal Time.zone.local(2026, 9, 8, 5, 0), @eight_clock.reload.clock_out
    assert_equal "off", @eight_clock.current_state
    assert_nil @half_past_clock.reload.clock_out

    travel_to(Time.zone.local(2026, 9, 8, 5, 30)) { AutoClockJob.perform_now }

    assert_equal Time.zone.local(2026, 9, 8, 5, 30), @half_past_clock.reload.clock_out
  end

  test "a late run clocks out at the shift end, not when it ran" do
    travel_to(Time.zone.local(2026, 9, 8, 9, 0)) { AutoClockJob.perform_now }

    assert_equal Time.zone.local(2026, 9, 8, 5, 0), @eight_clock.reload.clock_out
    assert_equal Time.zone.local(2026, 9, 8, 5, 30), @half_past_clock.reload.clock_out
  end

  test "a shift moved tonight ends at the new time" do
    @eight.update!(shift_time: Time.zone.local(2000, 1, 1, 20, 30))

    travel_to(Time.zone.local(2026, 9, 8, 5, 0)) { AutoClockJob.perform_now }

    assert_nil @eight_clock.reload.clock_out
  end
end

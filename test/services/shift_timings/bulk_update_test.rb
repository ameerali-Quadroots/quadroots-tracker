require "test_helper"

class ShiftTimings::BulkUpdateTest < ActiveSupport::TestCase
  def eight_pm
    Time.zone.local(2000, 1, 1, 20, 0)
  end

  test "changes every employed user when no departments are given" do
    result = ShiftTimings::BulkUpdate.new(shift_time: "20:00").call

    assert result.success?
    assert_equal User.employed.count, result.updated
    assert(User.employed.all? { |u| u.shift_time.strftime("%H:%M") == "20:00" })
  end

  test "changes only the chosen departments" do
    result = ShiftTimings::BulkUpdate.new(shift_time: "20:00", departments: [departments(:web)]).call

    assert_equal 3, result.updated
    assert_equal "20:00", users(:exec_web_a).reload.shift_time.strftime("%H:%M")
    assert_equal "18:00", users(:exec_design).reload.shift_time.strftime("%H:%M")
  end

  test "stores the same value the employee form would" do
    ShiftTimings::BulkUpdate.new(shift_time: "20:00", departments: [departments(:web)]).call
    users(:exec_design).update!(shift_time: eight_pm)

    assert_equal users(:exec_design).reload.shift_time, users(:exec_web_a).reload.shift_time
  end

  test "leaves former employees alone" do
    users(:exec_web_b).update!(employeed: false)

    result = ShiftTimings::BulkUpdate.new(shift_time: "20:00", departments: [departments(:web)]).call

    assert_equal 2, result.updated
    assert_equal "18:00", users(:exec_web_b).reload.shift_time.strftime("%H:%M")
  end

  test "count says how many would change without changing them" do
    update = ShiftTimings::BulkUpdate.new(shift_time: "20:00", departments: [departments(:web)])

    assert_equal 3, update.count
    assert_equal "18:00", users(:exec_web_a).reload.shift_time.strftime("%H:%M")
  end

  test "refuses a time it cannot read" do
    ["", "25:00", "8pm", "20:61", nil].each do |bad|
      result = ShiftTimings::BulkUpdate.new(shift_time: bad).call

      assert_not result.success?, "expected #{bad.inspect} to be refused"
      assert_equal 0, result.updated
    end
    assert_equal "18:00", users(:exec_web_a).reload.shift_time.strftime("%H:%M")
  end

  test "refuses an empty department list rather than changing everyone" do
    result = ShiftTimings::BulkUpdate.new(shift_time: "20:00", departments: []).call

    assert_not result.success?
    assert_equal "18:00", users(:exec_web_a).reload.shift_time.strftime("%H:%M")
  end
end

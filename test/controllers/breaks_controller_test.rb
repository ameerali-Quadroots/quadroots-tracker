require "test_helper"

# Starting and ending breaks from the home page.
class BreaksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:exec_web_a)
    sign_in @user
    @shift = TimeClock.create!(employee: @user, status: "on_time", clock_in: 3.hours.ago, current_state: "working")
  end

  def start_break(type = "Extra Break")
    post break_in_time_clock_breaks_path(@shift), params: { break_type: type }
  end

  test "starting a break opens one break" do
    start_break

    assert_redirected_to root_path
    assert_equal 1, @shift.breaks.where(break_out: nil).count
    assert_equal "On break", @shift.reload.current_state
  end

  test "starting a break while already on one does not open a second" do
    start_break
    start_break
    start_break("Meeting")

    assert_equal 1, @shift.breaks.count
    assert_equal "Extra Break", @shift.breaks.first.break_type
    assert_equal "On break", @shift.reload.current_state
    assert_match(/already on a break/i, flash[:alert].to_s)
  end

  test "ending a break closes every open break and returns to working" do
    # The state the bug left people in: several open breaks on one shift.
    first = Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 40.minutes.ago)
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 39.minutes.ago)
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 38.minutes.ago)
    @shift.update!(current_state: "On break")

    post break_out_time_clock_break_path(@shift, first)

    assert_equal 0, @shift.breaks.where(break_out: nil).count
    assert_equal "working", @shift.reload.current_state
    assert_not @shift.on_break?
  end

  test "an unknown break type is refused without an error page" do
    start_break("Nap")

    assert_redirected_to root_path
    assert_equal 0, @shift.breaks.count
  end

  test "the home page offers End Break, not Take Break, whenever a break is open" do
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 30.minutes.ago)                       # open
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 90.minutes.ago, break_out: 80.minutes.ago) # newer row, closed
    @shift.update!(current_state: "On break")

    get root_path

    assert_select "form[action*='break_out']", count: 1
    assert_select "div.dropdown.dropdown-premium", count: 0
    assert_select "[data-break-timer]", count: 1
  end

  test "the End Break button ends the break that is actually open" do
    open = Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 30.minutes.ago)
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 90.minutes.ago, break_out: 80.minutes.ago)
    @shift.update!(current_state: "On break")

    get root_path

    assert_select "form[action=?]", break_out_time_clock_break_path(@shift, open)
  end

  # The exact state the bug left people in: a break still open, but the shift
  # marked "working" because ending a different break reset it.
  test "someone stuck with an open break and a working state still gets a way to end it" do
    meeting = Break.create!(time_clock: @shift, break_type: "Meeting", break_in: 14.minutes.ago)
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 50.minutes.ago, break_out: 45.minutes.ago)
    @shift.update!(current_state: "working")

    get root_path

    assert_select "form[action=?] button", break_out_time_clock_break_path(@shift, meeting), text: /End Meeting/
    assert_select ".status-badge", text: /Meeting/
    assert_select ".status-badge", text: /working/i, count: 0
    assert_select "div.dropdown.dropdown-premium", count: 0
  end

  test "ending the break from that stuck state puts the shift back to working with nothing open" do
    meeting = Break.create!(time_clock: @shift, break_type: "Meeting", break_in: 14.minutes.ago)
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 13.minutes.ago)
    @shift.update!(current_state: "working")

    post break_out_time_clock_break_path(@shift, meeting)
    follow_redirect!

    assert_equal 0, @shift.breaks.where(break_out: nil).count
    assert_select "div.dropdown.dropdown-premium", count: 1
    assert_select "form[action*='break_out']", count: 0
  end

  test "the home page offers Take Break when no break is open" do
    Break.create!(time_clock: @shift, break_type: "Extra Break", break_in: 90.minutes.ago, break_out: 80.minutes.ago)

    get root_path

    assert_select "div.dropdown.dropdown-premium", count: 1
    assert_select "form[action*='break_out']", count: 0
  end
end

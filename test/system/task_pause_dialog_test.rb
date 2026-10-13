require "application_system_test_case"

# The pause dialog is the only thing standing between an executive and the rest
# of the page: it is modal, so while it is up nothing behind it can be clicked.
# Bootstrap refuses to hide a dialog that is still animating open, and a hide
# that never happens leaves the backdrop over the page for good — which is how
# "I paused one task and then could not start another" happens.
class TaskPauseDialogTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  setup do
    @executive = users(:exec_web_a)
    @executive.update!(password: "Passw0rd!123", password_confirmation: "Passw0rd!123")
    @first = tasks(:pending_a)
    @second = Task.create!(title: "Second task", priority: "normal", assigned_to: @executive,
                           assigned_by: users(:manager_web), task_type: task_types(:web_build))
    sign_in_as_executive
    visit my_tasks_tasks_path
    assert_text "My tasks"
  end

  test "a task can be started right after the pause dialog is used" do
    start_first_task
    pause_first_task
    assert_equal "paused", @first.reload.status

    find("[data-tm-action='#{start_task_path(@second)}']").click

    assert_selector ".tm-focus__title", text: "Second task"
    assert_equal "in_progress", @second.reload.status
  end

  test "a task can be started after a pause submitted while the dialog is still opening" do
    slow_the_dialog_animation
    start_first_task
    pause_first_task
    assert_equal "paused", @first.reload.status

    find("[data-tm-action='#{start_task_path(@second)}']").click

    assert_selector ".tm-focus__title", text: "Second task"
    assert_equal "in_progress", @second.reload.status
  end

  test "the pause dialog and its backdrop are gone once the pause lands" do
    slow_the_dialog_animation
    start_first_task
    pause_first_task

    assert_no_selector "#tm-pause-modal.show"
    assert_no_selector ".modal-backdrop"
    assert_no_selector "body.modal-open"
  end

  private

  def sign_in_as_executive
    visit new_user_session_path
    fill_in "user[email]", with: @executive.email
    fill_in "user[password]", with: "Passw0rd!123"
    find('input[type="submit"], button[type="submit"]').click
    assert_text "Signed in successfully"
  end

  # Stretches the dialog's opening animation so the window a fast click lands
  # in on a loaded machine is one every run of this test lands in.
  def slow_the_dialog_animation
    page.execute_script(<<~JS)
      var style = document.createElement("style");
      style.textContent =
        "#tm-pause-modal.fade .modal-dialog { transition: transform 5s linear !important; }";
      document.head.appendChild(style);
    JS
  end

  def start_first_task
    find("[data-tm-action='#{start_task_path(@first)}']").click
    assert_text "Running now"
  end

  def pause_first_task
    all("[data-tm-pause-url='#{pause_task_path(@first)}']").first.click
    assert_selector "#tm-pause-modal.show"
    fill_in "tm-pause-reason", with: "Switching to something urgent"
    find("#tm-pause-form button[type='submit']").click
    assert_text "Timer stopped"
  end
end

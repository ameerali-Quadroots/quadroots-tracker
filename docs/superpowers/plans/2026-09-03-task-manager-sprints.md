# Task Manager: Sprints, Subtasks, Team Hours & CSV — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a manager department-wide daily/weekly hour visibility for every executive, organise work as Client → Project → Sprint → Task → Subtask, and add CSV import of sprint work plus weekly/monthly hour exports.

**Architecture:** A new `task_work_sessions` table records every start/pause/resume/complete interval, split at midnight, making daily hour sums a plain grouped SQL aggregate. Tasks gain a self-referential `parent_id` (one level deep) and an optional `sprint_id`. All UI lands as tabs inside the existing `tasks/dashboard` page — no new pages.

**Tech Stack:** Rails 7.1.5, Ruby 3.1.2, PostgreSQL, Minitest + fixtures, Bootstrap 5 + ERB, Chart.js, `caxlsx` (already in Gemfile).

**Spec:** `docs/superpowers/specs/2026-09-03-task-manager-sprints-design.md`

## Global Constraints

- Ruby 3.1.2, Rails ~> 7.1.5. No new gems — `caxlsx` and Ruby's stdlib `CSV` cover the export/import needs.
- Every controller action stays behind the existing `authorize_page!("task_manager")` and `require_department_task_manager` filters. Do not weaken them.
- **Department is the security boundary.** Every query for tasks, hours, clients, projects and sprints must be scoped to `current_user.department_id`. Never scope by `assigned_by` alone, and never expose cross-department rows.
- Enum declarations use the Rails 7.0 keyword form already in this codebase: `enum status: { ... }, _default: "..."`.
- `TimeClock#total_duration` is **already net of breaks** (`app/models/time_clock.rb` `calculate_total_duration`). Never subtract `break_duration` from it again.
- The `users` "is employed" column is spelled `employeed` (sic). Use the `User.employed` scope, never the raw column.
- Executive role is matched by `access_role.name == "Executive"` (a `roles` row), not the legacy `users.role` string.
- Times are compared and bucketed in `Time.zone`, never UTC. Call `.in_time_zone` before any `beginning_of_day`.
- Run the whole suite with `bin/rails test`. Run one file with `bin/rails test test/models/foo_test.rb`.

## File Structure

**Created**
- `app/models/task_work_session.rb` — one work interval; owns midnight splitting.
- `app/models/client.rb`, `app/models/project.rb`, `app/models/sprint.rb` — the client hierarchy.
- `app/queries/reports/executive_hours.rb` — the department hours matrix. Query object, no AR callbacks.
- `app/services/task_csv_importer.rb` — parses + validates a CSV into row structs; dry-run and commit.
- `app/services/task_report_exporter.rb` — builds the three export row sets.
- `app/controllers/sprints_controller.rb` — client/project/sprint CRUD.
- `app/views/tasks/_tab_tasks.html.erb`, `_tab_team_hours.html.erb`, `_tab_sprints.html.erb`, `_task_row.html.erb`, `_import_modal.html.erb`, `_sprint_modal.html.erb`.

**Modified**
- `app/models/task.rb` — sessions, subtasks, sprint, department-scoped assignment validation.
- `app/controllers/tasks_controller.rb` — department scope, tabs, import, export.
- `app/views/tasks/dashboard.html.erb` — becomes a tab shell including the partials.
- `app/views/tasks/my_tasks.html.erb` — subtask nesting only.
- `config/routes.rb` — import/export/sprint routes.
- `test/fixtures/*.yml` — real fixtures (currently empty stubs).

---

## PHASE 1 — Work sessions, subtasks, department hours (Tasks 1–9)

Ships on its own. Delivers the visibility you asked for. Stop here safely.

---

### Task 1: Real test fixtures and a green baseline

The fixtures in `test/fixtures/users.yml` are the Rails-generated `one: {}` / `two: {}` stubs. `fixtures :all` loads them into every test, and every new test needs real departments, roles and users. Fix this before writing any feature test.

**Files:**
- Modify: `test/fixtures/users.yml`
- Create: `test/fixtures/departments.yml`, `test/fixtures/roles.yml`, `test/fixtures/task_types.yml`, `test/fixtures/user_managers.yml`, `test/fixtures/tasks.yml`

**Interfaces:**
- Produces: fixture names `departments(:web)`, `departments(:design)`, `roles(:manager)`, `roles(:executive)`, `users(:manager_web)`, `users(:exec_web_a)`, `users(:exec_web_b)`, `users(:exec_design)`, `task_types(:web_build)`, `tasks(:pending_a)`. Every later task uses these exact names.

- [ ] **Step 1: Record the current baseline**

Run: `bin/rails test 2>&1 | tail -30`

Write down the pass/fail counts. Do not assume it is green — the stub fixtures may already break it. If the test database does not exist, create it with `bin/rails db:test:prepare` and run again.

- [ ] **Step 2: Write the fixtures**

`test/fixtures/departments.yml`:

```yaml
web:
  name: Web
  code: WEB
  active: true
  task_manager_enabled: true

design:
  name: Design
  code: DSG
  active: true
  task_manager_enabled: true

sales:
  name: Sales
  code: SLS
  active: true
  task_manager_enabled: false
```

`test/fixtures/roles.yml`:

```yaml
manager:
  name: Manager
  slug: manager
  scope: employee
  rank: 20
  system: true
  active: true

executive:
  name: Executive
  slug: executive
  scope: employee
  rank: 40
  system: true
  active: true
```

`test/fixtures/users.yml` (replace the whole file — `encrypted_password` is a fixed bcrypt hash so Devise is satisfied without hashing on every load):

```yaml
manager_web:
  email: manager.web@example.com
  encrypted_password: "$2a$12$K8h/6yGZ2mS0uJ2m0iVnJeUj4H3Xb0hqfQ0h1bBrWk1cRUdE9GHiC"
  name: Web Manager
  role: Manager
  department: Web
  role_id: <%= ActiveRecord::FixtureSet.identify(:manager) %>
  department_id: <%= ActiveRecord::FixtureSet.identify(:web) %>
  employeed: true

exec_web_a:
  email: exec.web.a@example.com
  encrypted_password: "$2a$12$K8h/6yGZ2mS0uJ2m0iVnJeUj4H3Xb0hqfQ0h1bBrWk1cRUdE9GHiC"
  name: Web Exec A
  role: Executive
  department: Web
  role_id: <%= ActiveRecord::FixtureSet.identify(:executive) %>
  department_id: <%= ActiveRecord::FixtureSet.identify(:web) %>
  employeed: true

exec_web_b:
  email: exec.web.b@example.com
  encrypted_password: "$2a$12$K8h/6yGZ2mS0uJ2m0iVnJeUj4H3Xb0hqfQ0h1bBrWk1cRUdE9GHiC"
  name: Web Exec B
  role: Executive
  department: Web
  role_id: <%= ActiveRecord::FixtureSet.identify(:executive) %>
  department_id: <%= ActiveRecord::FixtureSet.identify(:web) %>
  employeed: true

exec_design:
  email: exec.design@example.com
  encrypted_password: "$2a$12$K8h/6yGZ2mS0uJ2m0iVnJeUj4H3Xb0hqfQ0h1bBrWk1cRUdE9GHiC"
  name: Design Exec
  role: Executive
  department: Design
  role_id: <%= ActiveRecord::FixtureSet.identify(:executive) %>
  department_id: <%= ActiveRecord::FixtureSet.identify(:design) %>
  employeed: true
```

`test/fixtures/user_managers.yml` — `exec_web_a` reports to the manager; `exec_web_b` deliberately does NOT, so Task 6 can prove department-scoped assignment works for a non-report:

```yaml
a_reports_to_manager:
  user: exec_web_a
  manager: manager_web
```

`test/fixtures/task_types.yml`:

```yaml
web_build:
  name: Build
  department: web
  sla_minutes: 120

web_fix:
  name: Fix
  department: web
  sla_minutes: 30
```

`test/fixtures/tasks.yml`:

```yaml
pending_a:
  title: Existing pending task
  priority: normal
  status: pending
  assigned_to: exec_web_a
  assigned_by: manager_web
  task_type: web_build
  accumulated_pause_seconds: 0
  auto_paused: false
  over_sla: false
```

- [ ] **Step 3: Write a test proving the fixtures load and relate correctly**

Create `test/models/fixture_sanity_test.rb`:

```ruby
require "test_helper"

class FixtureSanityTest < ActiveSupport::TestCase
  test "web department has task manager enabled and two executives" do
    assert departments(:web).task_manager_enabled?
    execs = User.employed.joins(:access_role)
                .where(department_id: departments(:web).id, roles: { name: "Executive" })
    assert_equal 2, execs.count
  end

  test "exec_web_b is in the department but does not report to the manager" do
    assert_equal departments(:web).id, users(:exec_web_b).department_id
    refute_includes users(:manager_web).direct_reports, users(:exec_web_b)
    assert_includes users(:manager_web).direct_reports, users(:exec_web_a)
  end
end
```

- [ ] **Step 4: Run it**

Run: `bin/rails test test/models/fixture_sanity_test.rb -v`
Expected: 2 runs, 0 failures. If `department_id` is nil, the ERB `identify` calls are wrong — check them before moving on.

- [ ] **Step 5: Run the whole suite**

Run: `bin/rails test`
Expected: no worse than the Step 1 baseline. If the new fixtures broke a previously passing test, fix it now.

- [ ] **Step 6: Commit**

```bash
git add test/fixtures test/models/fixture_sanity_test.rb
git commit -m "test: replace stub fixtures with real departments, roles and users"
```

---

### Task 2: TaskWorkSession model with midnight splitting

**Files:**
- Create: `app/models/task_work_session.rb`
- Create: migration via generator
- Test: `test/models/task_work_session_test.rb`
- Create: `test/fixtures/task_work_sessions.yml` (empty file with a `# no fixtures` comment — `fixtures :all` needs the table to exist, not rows)

**Interfaces:**
- Produces:
  - `TaskWorkSession.segments(start_time, end_time) -> Array<[Time, Time]>` — splits an interval at each midnight.
  - `TaskWorkSession.open_for(task, at: Time.current) -> TaskWorkSession`
  - `TaskWorkSession.close_for(task, at: Time.current) -> TaskWorkSession | nil`
  - `TaskWorkSession#close!(at) -> self`
  - Scopes: `.open_sessions`, `.closed_sessions`
  - Columns: `task_id`, `user_id`, `started_at`, `ended_at`, `duration_seconds`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateTaskWorkSessions
```

Fill the generated file with:

```ruby
class CreateTaskWorkSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :task_work_sessions do |t|
      t.references :task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_seconds, null: false, default: 0
      t.timestamps
    end

    add_index :task_work_sessions, %i[user_id started_at]
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 2: Create the empty fixture file**

`test/fixtures/task_work_sessions.yml`:

```yaml
# Sessions are created by the timer in tests, never loaded as fixtures.
```

- [ ] **Step 3: Write the failing test**

`test/models/task_work_session_test.rb`:

```ruby
require "test_helper"

class TaskWorkSessionTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:pending_a)
  end

  test "segments returns one segment for an interval inside a single day" do
    from = Time.zone.parse("2026-09-01 09:00")
    to   = Time.zone.parse("2026-09-01 11:30")

    segments = TaskWorkSession.segments(from, to)

    assert_equal [[from, to]], segments
  end

  test "segments splits an interval that crosses midnight" do
    from = Time.zone.parse("2026-09-01 22:00")
    to   = Time.zone.parse("2026-09-02 02:00")
    midnight = Time.zone.parse("2026-09-02 00:00")

    segments = TaskWorkSession.segments(from, to)

    assert_equal [[from, midnight], [midnight, to]], segments
  end

  test "segments splits an interval spanning three days" do
    from = Time.zone.parse("2026-09-01 23:00")
    to   = Time.zone.parse("2026-09-03 01:00")

    segments = TaskWorkSession.segments(from, to)

    assert_equal 3, segments.length
    assert_equal from, segments.first.first
    assert_equal to, segments.last.last
    assert_equal 26 * 3600, segments.sum { |a, b| (b - a).round }
  end

  test "segments returns nothing when the interval is empty or backwards" do
    now = Time.zone.parse("2026-09-01 09:00")

    assert_empty TaskWorkSession.segments(now, now)
    assert_empty TaskWorkSession.segments(now, now - 1.hour)
  end

  test "close! writes duration and leaves a single row for a same-day interval" do
    session = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 09:00"))

    session.close!(Time.zone.parse("2026-09-01 11:00"))

    assert_equal 1, TaskWorkSession.where(task_id: @task.id).count
    assert_equal 7200, session.reload.duration_seconds
    assert_equal Time.zone.parse("2026-09-01 11:00"), session.ended_at
  end

  test "close! splits a midnight-crossing session into two dated rows" do
    session = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 23:00"))

    session.close!(Time.zone.parse("2026-09-02 01:00"))

    rows = TaskWorkSession.where(task_id: @task.id).order(:started_at)
    assert_equal 2, rows.count
    assert_equal [3600, 3600], rows.map(&:duration_seconds)
    assert_equal [Date.new(2026, 9, 1), Date.new(2026, 9, 2)],
                 rows.map { |r| r.started_at.in_time_zone.to_date }
  end

  test "open_for records the task's assignee" do
    session = TaskWorkSession.open_for(@task)

    assert_equal @task.assigned_to_id, session.user_id
    assert_nil session.ended_at
  end

  test "close_for closes the newest open session and ignores closed ones" do
    old = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 09:00"))
    old.close!(Time.zone.parse("2026-09-01 10:00"))
    current = TaskWorkSession.open_for(@task, at: Time.zone.parse("2026-09-01 14:00"))

    TaskWorkSession.close_for(@task, at: Time.zone.parse("2026-09-01 15:00"))

    assert_equal 3600, current.reload.duration_seconds
    assert_equal 3600, old.reload.duration_seconds
  end

  test "close_for returns nil when there is no open session" do
    assert_nil TaskWorkSession.close_for(@task)
  end
end
```

- [ ] **Step 4: Run it and watch it fail**

Run: `bin/rails test test/models/task_work_session_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant TaskWorkSession`.

- [ ] **Step 5: Write the model**

`app/models/task_work_session.rb`:

```ruby
# One uninterrupted stretch of work on a task, written by the Task timer on
# start/pause/resume/complete. Sessions are the source of truth for *when* time
# was spent; Task#total_duration is only a cached rollup of them.
#
# A session is split at every midnight when it closes, so summing hours per day
# is a plain GROUP BY DATE(started_at) with no date arithmetic in the query.
class TaskWorkSession < ApplicationRecord
  belongs_to :task
  belongs_to :user

  validates :started_at, presence: true

  scope :open_sessions, -> { where(ended_at: nil) }
  scope :closed_sessions, -> { where.not(ended_at: nil) }

  # Splits [start_time, end_time) at each local midnight.
  # Returns [] for an empty or backwards interval.
  def self.segments(start_time, end_time)
    return [] if start_time.blank? || end_time.blank? || end_time <= start_time

    segments = []
    cursor = start_time
    while cursor < end_time
      next_midnight = cursor.in_time_zone.beginning_of_day + 1.day
      stop = [next_midnight, end_time].min
      segments << [cursor, stop]
      cursor = stop
    end
    segments
  end

  def self.open_for(task, at: Time.current)
    create!(task_id: task.id, user_id: task.assigned_to_id, started_at: at)
  end

  # Closes the task's most recent open session. Nil when none is open — which
  # happens for tasks that predate this table, so callers must tolerate it.
  def self.close_for(task, at: Time.current)
    session = where(task_id: task.id).open_sessions.order(:started_at).last
    session&.close!(at)
  end

  # Closes this session at `at`. The first day's slice updates this row; each
  # later day becomes its own row.
  def close!(at)
    slices = self.class.segments(started_at, at)
    return update!(ended_at: started_at, duration_seconds: 0) && self if slices.empty?

    transaction do
      first_from, first_to = slices.shift
      update!(ended_at: first_to, duration_seconds: (first_to - first_from).round)

      slices.each do |from, to|
        self.class.create!(task_id: task_id, user_id: user_id, started_at: from,
                           ended_at: to, duration_seconds: (to - from).round)
      end
    end
    self
  end
end
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bin/rails test test/models/task_work_session_test.rb -v`
Expected: 9 runs, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/models/task_work_session.rb db/migrate db/schema.rb test/models/task_work_session_test.rb test/fixtures/task_work_sessions.yml
git commit -m "feat: add TaskWorkSession with midnight-split work intervals"
```

---

### Task 3: Wire the Task timer to work sessions

**Files:**
- Modify: `app/models/task.rb` (`start!`, `pause!`, `resume!`, `complete!`)
- Test: `test/models/task_timer_sessions_test.rb`

**Interfaces:**
- Consumes: `TaskWorkSession.open_for`, `TaskWorkSession.close_for` from Task 2.
- Produces: `Task#work_sessions` association; `Task#total_duration` equals `work_sessions.sum(:duration_seconds)` after `complete!`.

- [ ] **Step 1: Write the failing test**

`test/models/task_timer_sessions_test.rb`:

```ruby
require "test_helper"

class TaskTimerSessionsTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:pending_a)
  end

  test "start opens a session" do
    travel_to Time.zone.parse("2026-09-01 09:00") do
      @task.start!
    end

    assert_equal 1, @task.work_sessions.count
    assert_nil @task.work_sessions.first.ended_at
  end

  test "pause closes the open session" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { @task.pause! }

    assert_equal 1, @task.work_sessions.count
    assert_equal 3600, @task.work_sessions.first.duration_seconds
  end

  test "resume opens a second session" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { @task.pause! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { @task.resume! }

    assert_equal 2, @task.work_sessions.count
    assert_equal 1, @task.work_sessions.open_sessions.count
  end

  test "complete closes the session and total_duration equals the session sum" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { @task.pause! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { @task.resume! }
    travel_to(Time.zone.parse("2026-09-01 12:00")) { @task.complete! }

    assert_equal 7200, @task.reload.total_duration
    assert_equal 7200, @task.work_sessions.sum(:duration_seconds)
    assert_equal 0, @task.work_sessions.open_sessions.count
  end

  test "a task already in progress before sessions existed still records its time" do
    @task.update_columns(status: "in_progress", started_at: Time.zone.parse("2026-09-01 09:00"))
    assert_equal 0, @task.work_sessions.count

    travel_to(Time.zone.parse("2026-09-01 11:00")) { @task.complete! }

    assert_equal 7200, @task.reload.total_duration
  end

  test "paused time is excluded from the session sum" do
    travel_to(Time.zone.parse("2026-09-01 09:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-01 09:30")) { @task.pause! }
    travel_to(Time.zone.parse("2026-09-01 11:30")) { @task.resume! }
    travel_to(Time.zone.parse("2026-09-01 12:00")) { @task.complete! }

    # 30 min before the pause + 30 min after it; the 2h pause is not counted.
    assert_equal 3600, @task.reload.total_duration
  end

  test "a task worked across midnight produces one session row per day" do
    travel_to(Time.zone.parse("2026-09-01 23:00")) { @task.start! }
    travel_to(Time.zone.parse("2026-09-02 01:00")) { @task.complete! }

    dates = @task.work_sessions.order(:started_at).map { |s| s.started_at.in_time_zone.to_date }
    assert_equal [Date.new(2026, 9, 1), Date.new(2026, 9, 2)], dates
    assert_equal 7200, @task.reload.total_duration
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/models/task_timer_sessions_test.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'work_sessions'`.

- [ ] **Step 3: Add the association**

In `app/models/task.rb`, directly below `belongs_to :task_type`:

```ruby
  has_many :work_sessions, class_name: "TaskWorkSession", dependent: :destroy
```

- [ ] **Step 4: Replace the four transition methods**

In `app/models/task.rb`, replace `start!`, `pause!`, `resume!` and `complete!` with:

```ruby
  def start!
    return false unless may_start?

    transaction do
      update!(status: :in_progress, started_at: Time.current)
      TaskWorkSession.open_for(self)
    end
    true
  end

  def pause!(reason: nil, auto: false)
    return false unless may_pause?

    transaction do
      TaskWorkSession.close_for(self)
      update!(status: :paused, pause_time: Time.current, reason: reason, auto_paused: auto)
    end
    true
  end

  def resume!
    return false unless may_resume?

    elapsed = pause_time.present? ? (Time.current - pause_time).to_i : 0
    transaction do
      update!(
        status: :in_progress,
        resume_time: Time.current,
        accumulated_pause_seconds: accumulated_pause_seconds + elapsed,
        pause_time: nil,
        auto_paused: false,
        reason: nil
      )
      TaskWorkSession.open_for(self)
    end
    true
  end

  def complete!
    return false unless may_complete?

    now = Time.current
    extra_pause = paused? && pause_time.present? ? (now - pause_time).to_i : 0

    transaction do
      TaskWorkSession.close_for(self, at: now)
      session_total = work_sessions.reload.sum(:duration_seconds)
      # A task that was already in progress when this table shipped has no
      # sessions to sum, so fall back to the original elapsed-minus-pauses
      # arithmetic rather than recording it as zero hours.
      final_duration = if session_total.positive?
                         session_total
                       else
                         (now - started_at).to_i - (accumulated_pause_seconds + extra_pause)
                       end
      update!(
        status: :completed,
        ended_at: now,
        accumulated_pause_seconds: accumulated_pause_seconds + extra_pause,
        total_duration: final_duration,
        over_sla: sla_seconds.positive? && final_duration > sla_seconds
      )
    end
    true
  end
```

Note: `pause!` closes the session *before* the status update so the close uses the pre-pause state; `complete!` closes first so the sum includes the final stretch.

- [ ] **Step 5: Run the new test**

Run: `bin/rails test test/models/task_timer_sessions_test.rb -v`
Expected: 7 runs, 0 failures.

- [ ] **Step 6: Run the whole suite for regressions**

Run: `bin/rails test`
Expected: no new failures versus the Task 1 baseline.

- [ ] **Step 7: Commit**

```bash
git add app/models/task.rb test/models/task_timer_sessions_test.rb
git commit -m "feat: record work sessions on every task timer transition"
```

---

### Task 4: Backfill work sessions for existing completed tasks

**Files:**
- Create: migration via generator
- Test: `test/models/task_work_session_backfill_test.rb`

**Interfaces:**
- Produces: `TaskWorkSession.backfill_completed_tasks! -> Integer` (count of tasks backfilled), callable from the migration and from tests.

- [ ] **Step 1: Write the failing test**

`test/models/task_work_session_backfill_test.rb`:

```ruby
require "test_helper"

class TaskWorkSessionBackfillTest < ActiveSupport::TestCase
  test "backfill creates one session per completed task ending at ended_at" do
    task = tasks(:pending_a)
    task.update_columns(status: "completed", total_duration: 3600,
                        started_at: Time.zone.parse("2026-09-01 09:00"),
                        ended_at: Time.zone.parse("2026-09-01 10:00"))

    assert_equal 1, TaskWorkSession.backfill_completed_tasks!

    session = task.work_sessions.sole
    assert_equal 3600, session.duration_seconds
    assert_equal Time.zone.parse("2026-09-01 10:00"), session.ended_at
    assert_equal task.assigned_to_id, session.user_id
  end

  test "backfill splits a completed task that spanned midnight" do
    task = tasks(:pending_a)
    task.update_columns(status: "completed", total_duration: 7200,
                        started_at: Time.zone.parse("2026-09-01 23:00"),
                        ended_at: Time.zone.parse("2026-09-02 01:00"))

    TaskWorkSession.backfill_completed_tasks!

    assert_equal 2, task.work_sessions.count
    assert_equal 7200, task.work_sessions.sum(:duration_seconds)
  end

  test "backfill skips tasks with no ended_at or no duration" do
    tasks(:pending_a).update_columns(status: "completed", total_duration: nil, ended_at: nil)

    assert_equal 0, TaskWorkSession.backfill_completed_tasks!
    assert_equal 0, TaskWorkSession.count
  end

  test "backfill is idempotent and never doubles a task's hours" do
    task = tasks(:pending_a)
    task.update_columns(status: "completed", total_duration: 3600,
                        started_at: Time.zone.parse("2026-09-01 09:00"),
                        ended_at: Time.zone.parse("2026-09-01 10:00"))

    TaskWorkSession.backfill_completed_tasks!
    TaskWorkSession.backfill_completed_tasks!

    assert_equal 1, task.work_sessions.count
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/models/task_work_session_backfill_test.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'backfill_completed_tasks!'`.

- [ ] **Step 3: Add the class method**

Append inside `class TaskWorkSession` in `app/models/task_work_session.rb`, above the final `end`:

```ruby
  # Gives tasks completed before this table existed a session each, so historic
  # weeks are not blank on the hours report. The interval is reconstructed
  # backwards from ended_at, which is the only timestamp we can trust — a task
  # paused for two days has a started_at that does not reflect worked time.
  def self.backfill_completed_tasks!
    scope = Task.where(status: "completed")
                .where.not(ended_at: nil)
                .where.not(total_duration: nil)
                .where(total_duration: 1..)
                .where.missing(:work_sessions)

    count = 0
    scope.find_each do |task|
      ends_at = task.ended_at.in_time_zone
      starts_at = ends_at - task.total_duration.seconds

      segments(starts_at, ends_at).each do |from, to|
        create!(task_id: task.id, user_id: task.assigned_to_id, started_at: from,
                ended_at: to, duration_seconds: (to - from).round)
      end
      count += 1
    end
    count
  end
```

`where.missing(:work_sessions)` is what makes it idempotent — it is Rails 6.1+ and available here.

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/models/task_work_session_backfill_test.rb -v`
Expected: 4 runs, 0 failures.

- [ ] **Step 5: Generate the data migration**

```bash
bin/rails generate migration BackfillTaskWorkSessions
```

Fill it with:

```ruby
class BackfillTaskWorkSessions < ActiveRecord::Migration[7.1]
  def up
    say_with_time "Backfilling work sessions from completed tasks" do
      TaskWorkSession.backfill_completed_tasks!
    end
  end

  def down
    # Only the reconstructed rows are removable; live timer rows must survive.
    # Distinguishing them is not possible after the fact, so this is one-way.
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 6: Run it**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: the migration reports a task count and completes.

- [ ] **Step 7: Commit**

```bash
git add app/models/task_work_session.rb db/migrate db/schema.rb test/models/task_work_session_backfill_test.rb
git commit -m "feat: backfill work sessions for tasks completed before the table existed"
```

---

### Task 5: Subtasks — one level deep

**Files:**
- Create: migration via generator
- Modify: `app/models/task.rb`
- Test: `test/models/task_subtask_test.rb`

**Interfaces:**
- Produces: `Task#parent`, `Task#subtasks`, `Task#subtask?`, `Task#parent_task?`, `Task#rolled_up_duration_seconds`, `Task#subtask_progress -> [done, total]`. Scopes `Task.top_level`, `Task.subtasks_only`.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddParentAndPositionToTasks
```

Fill it with:

```ruby
class AddParentAndPositionToTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :tasks, :parent, foreign_key: { to_table: :tasks }, null: true
    add_column :tasks, :position, :integer, null: false, default: 0
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 2: Write the failing test**

`test/models/task_subtask_test.rb`:

```ruby
require "test_helper"

class TaskSubtaskTest < ActiveSupport::TestCase
  setup do
    @parent = tasks(:pending_a)
  end

  def build_subtask(parent:, assigned_to: users(:exec_web_a))
    Task.new(title: "Sub", priority: "normal", parent: parent,
             assigned_to: assigned_to, assigned_by: users(:manager_web),
             task_type: task_types(:web_build))
  end

  test "a task can have subtasks" do
    subtask = build_subtask(parent: @parent)

    assert subtask.save, subtask.errors.full_messages.to_sentence
    assert_equal [subtask], @parent.reload.subtasks.to_a
    assert subtask.subtask?
    assert @parent.parent_task?
  end

  test "a subtask cannot itself have a subtask" do
    subtask = build_subtask(parent: @parent)
    subtask.save!

    grandchild = build_subtask(parent: subtask)

    refute grandchild.valid?
    assert_includes grandchild.errors[:parent], "cannot be a subtask itself"
  end

  test "a task cannot be its own parent" do
    @parent.parent_id = @parent.id

    refute @parent.valid?
    assert_includes @parent.errors[:parent], "cannot be the task itself"
  end

  test "top_level excludes subtasks" do
    build_subtask(parent: @parent).save!

    assert_includes Task.top_level, @parent
    assert_equal 1, Task.subtasks_only.count
  end

  test "rolled up duration includes subtask hours" do
    subtask = build_subtask(parent: @parent)
    subtask.save!
    travel_to(Time.zone.parse("2026-09-01 09:00")) { subtask.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { subtask.complete! }

    assert_equal 3600, @parent.reload.rolled_up_duration_seconds
  end

  test "subtask progress counts completed children" do
    a = build_subtask(parent: @parent)
    a.save!
    b = build_subtask(parent: @parent)
    b.save!
    travel_to(Time.zone.parse("2026-09-01 09:00")) { a.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { a.complete! }

    assert_equal [1, 2], @parent.reload.subtask_progress
  end

  test "destroying a parent destroys its subtasks" do
    build_subtask(parent: @parent).save!

    assert_difference -> { Task.count }, -2 do
      @parent.destroy
    end
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

Run: `bin/rails test test/models/task_subtask_test.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'subtasks'`.

- [ ] **Step 4: Implement**

In `app/models/task.rb`, add below the `has_many :work_sessions` line:

```ruby
  belongs_to :parent, class_name: "Task", optional: true
  has_many :subtasks, class_name: "Task", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
```

Add to the scopes block:

```ruby
  scope :top_level, -> { where(parent_id: nil) }
  scope :subtasks_only, -> { where.not(parent_id: nil) }
```

Add to the validations block:

```ruby
  validate :parent_is_not_a_subtask
```

Add these public methods above the `private` keyword:

```ruby
  def subtask? = parent_id.present?
  def parent_task? = subtasks.any?

  # A parent's real cost is its own logged time plus everything its children
  # logged — including children assigned to a different executive.
  def rolled_up_duration_seconds
    live_duration_seconds + subtasks.sum(&:live_duration_seconds)
  end

  def subtask_progress
    children = subtasks.to_a
    [children.count(&:completed?), children.size]
  end
```

Add these private methods:

```ruby
  # Jira and ClickUp both stop at one level of nesting, and so do we: deeper
  # trees make the rollup recursive and the CSV parent column ambiguous.
  def parent_is_not_a_subtask
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent, "cannot be the task itself")
    elsif parent&.parent_id.present?
      errors.add(:parent, "cannot be a subtask itself")
    end
  end
```

- [ ] **Step 5: Run the test**

Run: `bin/rails test test/models/task_subtask_test.rb -v`
Expected: 7 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/models/task.rb db/migrate db/schema.rb test/models/task_subtask_test.rb
git commit -m "feat: add one-level subtasks with duration rollup"
```

---

### Task 6: Department-scoped task assignment

Replaces the direct-report requirement so sprint work can be assigned to any executive in the department.

**Files:**
- Modify: `app/models/task.rb:120` (`assigned_to_is_a_direct_report_executive`)
- Test: `test/models/task_assignment_scope_test.rb`

**Interfaces:**
- Produces: validation `assigned_to_is_a_department_executive`. The old method name disappears.

- [ ] **Step 1: Write the failing test**

`test/models/task_assignment_scope_test.rb`:

```ruby
require "test_helper"

class TaskAssignmentScopeTest < ActiveSupport::TestCase
  def build_task(assigned_to:)
    Task.new(title: "T", priority: "normal", assigned_to: assigned_to,
             assigned_by: users(:manager_web), task_type: task_types(:web_build))
  end

  test "assigning to a direct report in the department is valid" do
    assert build_task(assigned_to: users(:exec_web_a)).valid?
  end

  test "assigning to a department executive who is not a direct report is valid" do
    task = build_task(assigned_to: users(:exec_web_b))

    assert task.valid?, task.errors.full_messages.to_sentence
  end

  test "assigning to an executive in another department is invalid" do
    task = build_task(assigned_to: users(:exec_design))

    refute task.valid?
    assert_includes task.errors[:assigned_to], "must be an Executive in your department"
  end

  test "assigning to a non-executive is invalid" do
    task = build_task(assigned_to: users(:manager_web))

    refute task.valid?
    assert_includes task.errors[:assigned_to], "must hold the Executive role"
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/models/task_assignment_scope_test.rb -v`
Expected: FAIL on "not a direct report is valid" — the current validation rejects it.

- [ ] **Step 3: Replace the validation**

In `app/models/task.rb`, change the validation declaration from:

```ruby
  validate :assigned_to_is_a_direct_report_executive
```

to:

```ruby
  validate :assigned_to_is_a_department_executive
```

and replace the private method body with:

```ruby
  # Department, not direct reports, is the assignment boundary: sprint work gets
  # handed to whoever in the department is free, including executives who report
  # to another manager.
  def assigned_to_is_a_department_executive
    return if assigned_by.blank? || assigned_to.blank?

    if assigned_to.department_id.blank? || assigned_to.department_id != assigned_by.department_id
      errors.add(:assigned_to, "must be an Executive in your department")
    end

    unless assigned_to.access_role&.name == "Executive"
      errors.add(:assigned_to, "must hold the Executive role")
    end
  end
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/models/task_assignment_scope_test.rb -v`
Expected: 4 runs, 0 failures.

- [ ] **Step 5: Check nothing else referenced the old method name**

Run: `grep -rn "assigned_to_is_a_direct_report_executive" app test`
Expected: no output.

- [ ] **Step 6: Run the whole suite**

Run: `bin/rails test`
Expected: no new failures.

- [ ] **Step 7: Commit**

```bash
git add app/models/task.rb test/models/task_assignment_scope_test.rb
git commit -m "feat: allow assigning tasks to any executive in the department"
```

---

### Task 7: Reports::ExecutiveHours query object

**Files:**
- Create: `app/queries/reports/executive_hours.rb`
- Test: `test/queries/reports/executive_hours_test.rb`

**Interfaces:**
- Produces:
  - `Reports::ExecutiveHours.new(department:, range:)`
  - `#executives -> ActiveRecord::Relation<User>` ordered by name
  - `#matrix -> { user_id => { Date => { task_seconds:, attendance_seconds:, gap_seconds: } } }`
  - `#for(user_id, date) -> Hash` with the three keys, zeroed when absent
  - `#totals_for(user_id) -> Hash` with the three keys summed across the range
  - `#dates -> Array<Date>`
  - `#bucket(user_id, dates) -> Hash` with the three keys summed over those dates
  - `#columns(period) -> Array<[String, Array<Date>]>` — one entry per day for
    `"week"`, one per week-of-month for `"month"`
- Autoload note: `app/queries` is picked up by Zeitwerk automatically because `config.autoload_lib` is not what governs `app/*` — every directory under `app/` is an autoload root in Rails 7.1. No config change needed.

- [ ] **Step 1: Write the failing test**

`test/queries/reports/executive_hours_test.rb`:

```ruby
require "test_helper"

module Reports
  class ExecutiveHoursTest < ActiveSupport::TestCase
    setup do
      @department = departments(:web)
      @range = Time.zone.parse("2026-09-01 00:00")..Time.zone.parse("2026-09-07 23:59:59")
      @exec = users(:exec_web_a)
    end

    def report = Reports::ExecutiveHours.new(department: @department, range: @range)

    test "lists employed executives in the department, ordered by name" do
      names = report.executives.map(&:name)

      assert_equal ["Web Exec A", "Web Exec B"], names
      refute_includes names, "Design Exec"
      refute_includes names, "Web Manager"
    end

    test "sums task seconds per executive per day" do
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

      assert_equal 7200, report.for(@exec.id, Date.new(2026, 9, 1))[:task_seconds]
    end

    test "sums attendance seconds from time clocks without re-subtracting breaks" do
      TimeClock.create!(user_id: @exec.id,
                        clock_in: Time.zone.parse("2026-09-01 09:00"),
                        clock_out: Time.zone.parse("2026-09-01 18:00"),
                        total_duration: 28_800, break_duration: 3600)

      assert_equal 28_800, report.for(@exec.id, Date.new(2026, 9, 1))[:attendance_seconds]
    end

    test "gap is attendance minus task time, never negative" do
      TimeClock.create!(user_id: @exec.id,
                        clock_in: Time.zone.parse("2026-09-01 09:00"),
                        clock_out: Time.zone.parse("2026-09-01 18:00"),
                        total_duration: 28_800, break_duration: 0)
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

      day = report.for(@exec.id, Date.new(2026, 9, 1))
      assert_equal 21_600, day[:gap_seconds]
    end

    test "columns yields one entry per day for a week and per week for a month" do
      month = Reports::ExecutiveHours.new(
        department: @department,
        range: Time.zone.parse("2026-09-01 00:00")..Time.zone.parse("2026-09-30 23:59:59")
      )

      assert_equal 7, report.columns("week").size
      assert_equal 5, month.columns("month").size
      assert_equal "w/c 31 Aug", month.columns("month").first.first
    end

    test "bucket sums several days into one cell" do
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

      summed = report.bucket(@exec.id, [Date.new(2026, 9, 1), Date.new(2026, 9, 2)])

      assert_equal 7200, summed[:task_seconds]
    end

    test "returns zeros for a day with no activity" do
      assert_equal({ task_seconds: 0, attendance_seconds: 0, gap_seconds: 0 },
                   report.for(@exec.id, Date.new(2026, 9, 4)))
    end

    test "excludes activity outside the range" do
      task = tasks(:pending_a)
      travel_to(Time.zone.parse("2026-08-25 09:00")) { task.start! }
      travel_to(Time.zone.parse("2026-08-25 11:00")) { task.complete! }

      assert_equal 0, report.totals_for(@exec.id)[:task_seconds]
    end

    test "subtask hours count toward whoever worked them, not the parent's assignee" do
      subtask = Task.create!(title: "Sub", priority: "normal", parent: tasks(:pending_a),
                             assigned_to: users(:exec_web_b), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))
      travel_to(Time.zone.parse("2026-09-02 09:00")) { subtask.start! }
      travel_to(Time.zone.parse("2026-09-02 10:00")) { subtask.complete! }

      assert_equal 3600, report.for(users(:exec_web_b).id, Date.new(2026, 9, 2))[:task_seconds]
      assert_equal 0, report.for(@exec.id, Date.new(2026, 9, 2))[:task_seconds]
    end

    test "query count does not grow with the number of executives" do
      queries = []
      counter = ->(_n, _s, _f, _i, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        report.tap(&:executives).matrix
      end

      # executives + task sessions + time clocks. Anything more means the
      # aggregate degraded into per-user queries.
      assert_operator queries.size, :<=, 4, "N+1 detected:\n#{queries.join("\n")}"
    end
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/queries/reports/executive_hours_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant Reports`.

- [ ] **Step 3: Write the query object**

`app/queries/reports/executive_hours.rb`:

```ruby
module Reports
  # Daily task-time and attendance-time per executive for one department.
  #
  # Built from exactly two grouped aggregates no matter how many executives or
  # days are in range. This is the known N+1 hazard in this codebase (the
  # TimeClock breaks lookups that ignore eager loads), so never iterate records
  # to sum here — a test asserts the query count.
  class ExecutiveHours
    EMPTY_DAY = { task_seconds: 0, attendance_seconds: 0, gap_seconds: 0 }.freeze

    def initialize(department:, range:)
      @department = department
      @range = range
    end

    def executives
      @executives ||= User.employed
                          .joins(:access_role)
                          .where(department_id: @department&.id, roles: { name: "Executive" })
                          .order(:name)
    end

    def dates
      @dates ||= (@range.begin.to_date..@range.end.to_date).to_a
    end

    def matrix
      @matrix ||= build_matrix
    end

    def for(user_id, date)
      matrix.dig(user_id, date) || EMPTY_DAY
    end

    # Sums several days into one cell. The month view shows weeks-of-month
    # columns rather than thirty day columns, and reuses the already-built
    # matrix instead of re-querying.
    def bucket(user_id, dates)
      dates.reduce(EMPTY_DAY.dup) do |acc, date|
        cell = self.for(user_id, date)
        { task_seconds: acc[:task_seconds] + cell[:task_seconds],
          attendance_seconds: acc[:attendance_seconds] + cell[:attendance_seconds],
          gap_seconds: acc[:gap_seconds] + cell[:gap_seconds] }
      end
    end

    def columns(period)
      if period == "month"
        dates.group_by(&:beginning_of_week)
             .map { |week_start, days| ["w/c #{week_start.strftime('%d %b')}", days] }
      else
        dates.map { |date| [date.strftime("%d %b"), [date]] }
      end
    end

    def totals_for(user_id)
      days = matrix[user_id]&.values || []
      {
        task_seconds: days.sum { |d| d[:task_seconds] },
        attendance_seconds: days.sum { |d| d[:attendance_seconds] },
        gap_seconds: days.sum { |d| d[:gap_seconds] }
      }
    end

    private

    def build_matrix
      ids = executives.map(&:id)
      return {} if ids.empty?

      task = TaskWorkSession.where(user_id: ids, started_at: @range)
                            .group(:user_id, Arel.sql("DATE(started_at)"))
                            .sum(:duration_seconds)

      # total_duration is already net of breaks (TimeClock#calculate_total_duration).
      # Subtracting break_duration here would double-count them.
      attendance = TimeClock.where(user_id: ids, clock_in: @range)
                            .group(:user_id, Arel.sql("DATE(clock_in)"))
                            .sum(Arel.sql("COALESCE(total_duration, 0)"))

      result = Hash.new { |h, k| h[k] = {} }

      merge_into(result, task, :task_seconds)
      merge_into(result, attendance, :attendance_seconds)

      result.each_value do |days|
        days.each_value do |cell|
          cell[:gap_seconds] = [cell[:attendance_seconds] - cell[:task_seconds], 0].max
        end
      end
      result
    end

    def merge_into(result, aggregate, key)
      aggregate.each do |(user_id, date), seconds|
        date = date.to_date
        cell = (result[user_id][date] ||= { task_seconds: 0, attendance_seconds: 0, gap_seconds: 0 })
        cell[key] = seconds.to_i
      end
    end
  end
end
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/queries/reports/executive_hours_test.rb -v`
Expected: 10 runs, 0 failures. If the N+1 test fails, the `sum` calls have been replaced by Ruby-side iteration — put them back.

- [ ] **Step 5: Commit**

```bash
git add app/queries test/queries
git commit -m "feat: add Reports::ExecutiveHours department hours query"
```

---

### Task 8: Dashboard — department scope, tabs, and the Team Hours grid

**Files:**
- Modify: `app/controllers/tasks_controller.rb` (`dashboard`)
- Modify: `app/views/tasks/dashboard.html.erb`
- Create: `app/views/tasks/_tab_tasks.html.erb`, `app/views/tasks/_tab_team_hours.html.erb`, `app/views/tasks/_task_row.html.erb`
- Test: `test/controllers/tasks_dashboard_test.rb`

**Interfaces:**
- Consumes: `Reports::ExecutiveHours` (Task 7), `Task.top_level` / `#subtasks` (Task 5).
- Produces: controller ivars `@tasks`, `@executives`, `@task_types`, `@stats`, `@over_sla_count`, `@tasks_per_executive`, `@hours_report`, `@week_start`, `@period`, `@task`. Helper `TasksController#department_tasks`.

- [ ] **Step 1: Write the failing test**

`test/controllers/tasks_dashboard_test.rb`:

```ruby
require "test_helper"

class TasksDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @manager = users(:manager_web)
    sign_in @manager
  end

  test "dashboard shows tasks assigned by another manager in the same department" do
    other_manager = User.create!(
      email: "other.manager@example.com", password: "password123", name: "Other Manager",
      role_id: roles(:manager).id, department_id: departments(:web).id, employeed: true
    )
    UserManager.create!(user: users(:exec_web_b), manager: other_manager)
    task = Task.create!(title: "Assigned by peer", priority: "normal",
                        assigned_to: users(:exec_web_b), assigned_by: other_manager,
                        task_type: task_types(:web_build))

    get dashboard_tasks_path

    assert_response :success
    assert_includes response.body, task.title
  end

  test "dashboard never shows another department's tasks" do
    design_manager = User.create!(
      email: "design.manager@example.com", password: "password123", name: "Design Manager",
      role_id: roles(:manager).id, department_id: departments(:design).id, employeed: true
    )
    hidden = Task.create!(title: "Design department secret", priority: "normal",
                          assigned_to: users(:exec_design), assigned_by: design_manager,
                          task_type: TaskType.create!(name: "Mock", department: departments(:design), sla_minutes: 10))

    get dashboard_tasks_path

    refute_includes response.body, hidden.title
  end

  test "dashboard renders the team hours tab with every department executive" do
    get dashboard_tasks_path

    assert_response :success
    assert_includes response.body, "Team Hours"
    assert_includes response.body, "Web Exec A"
    assert_includes response.body, "Web Exec B"
  end

  test "subtasks are not listed as top level rows" do
    Task.create!(title: "A subtask row", priority: "normal", parent: tasks(:pending_a),
                 assigned_to: users(:exec_web_a), assigned_by: @manager,
                 task_type: task_types(:web_build))

    get dashboard_tasks_path

    assert_equal 1, css_select("tbody tr.task-row--top").size
  end

  test "week param moves the hours window" do
    get dashboard_tasks_path(week_start: "2026-09-07")

    assert_response :success
    assert_includes response.body, "07 Sep"
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/tasks_dashboard_test.rb -v`
Expected: FAIL — the peer-assigned task is absent because `dashboard` still scopes by `for_manager`.

- [ ] **Step 3: Rewrite the dashboard action**

In `app/controllers/tasks_controller.rb`, replace the `dashboard` method with:

```ruby
  def dashboard
    @period = params[:period] == "month" ? "month" : "week"
    @week_start = parse_week_start

    @tasks = department_tasks.top_level
                             .includes(:assigned_to, :task_type, subtasks: %i[assigned_to task_type])
                             .order(created_at: :desc)
    @tasks = @tasks.where(status: params[:status]) if params[:status].present?
    @tasks = @tasks.where(assigned_to_id: params[:executive_id]) if params[:executive_id].present?
    @tasks = @tasks.where(assigned_by_id: current_user.id) if params[:mine] == "1"

    @executives = department_executives
    @task_types = TaskType.where(department_id: current_user.department_id).order(:name)
    @stats = department_tasks.group(:status).count
    @over_sla_count = department_tasks.includes(:task_type).count(&:over_sla?)
    @tasks_per_executive = department_tasks.joins(:assigned_to).group("users.name").count

    @hours_report = Reports::ExecutiveHours.new(department: current_user.org_department, range: hours_range)
    @task = Task.new
  end
```

Add these private methods to the same controller:

```ruby
  # Department is the visibility boundary, not "tasks I assigned" — a manager
  # needs to see what every executive in the department is carrying.
  def department_tasks
    Task.joins(:assigned_to).where(users: { department_id: current_user.department_id })
  end

  def department_executives
    User.employed.joins(:access_role)
        .where(department_id: current_user.department_id, roles: { name: "Executive" })
        .order(:name)
  end

  def parse_week_start
    (Date.parse(params[:week_start]) rescue Date.current).beginning_of_week
  end

  def hours_range
    if @period == "month"
      @week_start.beginning_of_month.beginning_of_day..@week_start.end_of_month.end_of_day
    else
      @week_start.beginning_of_day..(@week_start + 6.days).end_of_day
    end
  end
```

- [ ] **Step 4: Extract the tasks table into a partial**

Create `app/views/tasks/_task_row.html.erb`:

```erb
<tr class="<%= task.parent_id.present? ? 'task-row--sub' : 'task-row--top' %>">
  <td>
    <div class="fw-semibold">
      <% if task.parent_id.present? %>
        <i class="fa-solid fa-turn-up fa-rotate-90 text-muted me-2 small"></i>
      <% end %>
      <%= task.title %>
      <% if task.parent_id.blank? %>
        <% done, total = task.subtask_progress %>
        <% if total.positive? %>
          <span class="badge bg-secondary ms-2"><%= done %>/<%= total %></span>
        <% end %>
      <% end %>
    </div>
    <% if task.description.present? %>
      <div class="text-muted small"><%= truncate(task.description, length: 60) %></div>
    <% end %>
  </td>
  <td><%= task.assigned_to&.name %></td>
  <td><%= task.task_type&.name %> · <%= task.formatted_sla %></td>
  <td><span class="status-tag status-tag--<%= task.status %>"><%= task.status.humanize %></span></td>
  <td><%= task.priority.capitalize %></td>
  <td><%= task.due_date&.strftime("%d %b %Y") || "—" %></td>
  <td><%= task.formatted_duration(task.parent_id.blank? ? task.rolled_up_duration_seconds : task.live_duration_seconds) %></td>
</tr>
```

Create `app/views/tasks/_tab_tasks.html.erb` by moving the existing `task-panel-dark` block out of `dashboard.html.erb` verbatim, then replacing its `<tbody>` with:

```erb
          <tbody>
            <% @tasks.each do |task| %>
              <%= render "tasks/task_row", task: task %>
              <% task.subtasks.each do |subtask| %>
                <%= render "tasks/task_row", task: subtask %>
              <% end %>
            <% end %>
          </tbody>
```

and adding an "Assigned by me" pill next to the existing status pills:

```erb
        <%= link_to "Assigned by me",
              dashboard_tasks_path(status: params[:status], executive_id: params[:executive_id], mine: "1"),
              class: "task-filter-pill #{'active' if params[:mine] == '1'}" %>
```

- [ ] **Step 5: Build the Team Hours tab**

Create `app/views/tasks/_tab_team_hours.html.erb`:

```erb
<div class="task-panel-dark">
  <div class="task-panel-dark__header">
    <h3 class="task-panel-dark__title">Team Hours</h3>
    <div class="task-panel-dark__controls">
      <div class="task-filter-pills">
        <%= link_to "Week", dashboard_tasks_path(tab: "team_hours", period: "week", week_start: @week_start),
              class: "task-filter-pill #{'active' if @period == 'week'}" %>
        <%= link_to "Month", dashboard_tasks_path(tab: "team_hours", period: "month", week_start: @week_start),
              class: "task-filter-pill #{'active' if @period == 'month'}" %>
      </div>
      <%= link_to dashboard_tasks_path(tab: "team_hours", period: @period, week_start: @week_start - 7.days),
            class: "btn btn-outline-premium btn-premium btn-sm" do %>
        <i class="fa-solid fa-chevron-left"></i>
      <% end %>
      <span class="text-muted small mx-2">
        <%= @hours_report.dates.first.strftime("%d %b") %> – <%= @hours_report.dates.last.strftime("%d %b %Y") %>
      </span>
      <%= link_to dashboard_tasks_path(tab: "team_hours", period: @period, week_start: @week_start + 7.days),
            class: "btn btn-outline-premium btn-premium btn-sm" do %>
        <i class="fa-solid fa-chevron-right"></i>
      <% end %>
    </div>
  </div>

  <div class="task-panel-dark__body">
    <div class="table-responsive">
      <table class="table align-middle mb-0 task-table">
        <thead>
          <tr>
            <th>Executive</th>
            <% @hours_report.columns(@period).each do |label, days| %>
              <th class="text-center">
                <%= label %>
                <div class="text-muted small"><%= days.one? ? days.first.strftime("%a") : "#{days.size} days" %></div>
              </th>
            <% end %>
            <th class="text-center">Total</th>
            <th class="text-center">Untracked</th>
          </tr>
        </thead>
        <tbody>
          <% @hours_report.executives.each do |executive| %>
            <tr>
              <td class="fw-semibold"><%= executive.name %></td>
              <% @hours_report.columns(@period).each do |_label, days| %>
                <% cell = @hours_report.bucket(executive.id, days) %>
                <td class="text-center">
                  <div class="fw-semibold"><%= hours_label(cell[:task_seconds]) %></div>
                  <div class="text-muted small"><%= hours_label(cell[:attendance_seconds]) %></div>
                </td>
              <% end %>
              <% totals = @hours_report.totals_for(executive.id) %>
              <td class="text-center fw-bold">
                <div><%= hours_label(totals[:task_seconds]) %></div>
                <div class="text-muted small"><%= hours_label(totals[:attendance_seconds]) %></div>
              </td>
              <td class="text-center"><%= hours_label(totals[:gap_seconds]) %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    <p class="text-muted small mt-3 mb-0">
      Top figure is time logged on tasks. Grey figure below it is attendance from the time clock. Untracked is the difference.
    </p>
  </div>
</div>
```

Add the `hours_label` helper to `app/helpers/tasks_helper.rb` (create the file if it does not exist):

```ruby
module TasksHelper
  def hours_label(seconds)
    seconds = seconds.to_i
    return "—" if seconds.zero?

    h, rem = seconds.divmod(3600)
    m, = rem.divmod(60)
    h.positive? ? "#{h}h #{m}m" : "#{m}m"
  end
end
```

- [ ] **Step 6: Turn dashboard.html.erb into the tab shell**

In `app/views/tasks/dashboard.html.erb`, keep the header card, the stat cards and the two chart cards as they are. Replace everything from `<div class="task-panel-dark">` to its closing tag with:

```erb
<ul class="nav nav-tabs task-tabs mb-3" role="tablist">
  <li class="nav-item">
    <button class="nav-link <%= 'active' if params[:tab].blank? || params[:tab] == 'tasks' %>"
            data-bs-toggle="tab" data-bs-target="#tab-tasks" type="button">Tasks</button>
  </li>
  <li class="nav-item">
    <button class="nav-link <%= 'active' if params[:tab] == 'team_hours' %>"
            data-bs-toggle="tab" data-bs-target="#tab-team-hours" type="button">Team Hours</button>
  </li>
</ul>

<div class="tab-content">
  <div class="tab-pane fade <%= 'show active' if params[:tab].blank? || params[:tab] == 'tasks' %>" id="tab-tasks">
    <%= render "tasks/tab_tasks" %>
  </div>
  <div class="tab-pane fade <%= 'show active' if params[:tab] == 'team_hours' %>" id="tab-team-hours">
    <%= render "tasks/tab_team_hours" %>
  </div>
</div>
```

- [ ] **Step 7: Run the test**

Run: `bin/rails test test/controllers/tasks_dashboard_test.rb -v`
Expected: 5 runs, 0 failures.

- [ ] **Step 8: Look at the page**

Start the server and open `/tasks/dashboard` as a Web-department manager. Confirm both tabs render and the hours grid shows two executives. If CSS looks stale, delete `public/assets` and restart — precompiled assets shadow `app/assets` in development in this project.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/tasks_controller.rb app/views/tasks app/helpers/tasks_helper.rb test/controllers/tasks_dashboard_test.rb
git commit -m "feat: department-wide task dashboard with a Team Hours tab"
```

---

### Task 9: Nest subtasks on My Tasks

**Files:**
- Modify: `app/controllers/tasks_controller.rb` (`my_tasks`)
- Modify: `app/views/tasks/my_tasks.html.erb`
- Test: `test/controllers/tasks_my_tasks_test.rb`

**Interfaces:**
- Consumes: `Task.top_level`, `Task#subtasks` (Task 5).
- Produces: `@tasks` on `my_tasks` contains only top-level tasks plus tasks whose parent belongs to someone else.

- [ ] **Step 1: Write the failing test**

`test/controllers/tasks_my_tasks_test.rb`:

```ruby
require "test_helper"

class TasksMyTasksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:exec_web_a) }

  test "a subtask appears once, nested, not as its own top level row" do
    Task.create!(title: "Nested child", priority: "normal", parent: tasks(:pending_a),
                 assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                 task_type: task_types(:web_build))

    get my_tasks_tasks_path

    assert_response :success
    assert_equal 1, response.body.scan("Nested child").size
  end

  test "a subtask whose parent belongs to another executive still appears" do
    parent = Task.create!(title: "Someone else's parent", priority: "normal",
                          assigned_to: users(:exec_web_b), assigned_by: users(:manager_web),
                          task_type: task_types(:web_build))
    Task.create!(title: "Orphan-looking child", priority: "normal", parent: parent,
                 assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                 task_type: task_types(:web_build))

    get my_tasks_tasks_path

    assert_includes response.body, "Orphan-looking child"
    refute_includes response.body, "Someone else's parent"
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/tasks_my_tasks_test.rb -v`
Expected: FAIL — "Nested child" appears twice (once flat, once nested) or the second test's child is missing.

- [ ] **Step 3: Rewrite the action**

Replace `my_tasks` in `app/controllers/tasks_controller.rb`:

```ruby
  def my_tasks
    mine = Task.for_executive(current_user)
    # A subtask is nested under its parent only when the parent is also mine;
    # otherwise it would silently vanish from the executive's list.
    nested_ids = mine.subtasks_only.where(parent_id: mine.select(:id)).pluck(:id)

    @tasks = mine.where.not(id: nested_ids)
                 .includes(:task_type, subtasks: :task_type)
                 .order(created_at: :desc)
  end
```

- [ ] **Step 4: Extract the task card into a partial**

`app/views/tasks/my_tasks.html.erb` currently has, at line 52, `<% @tasks.each do |task| %>`, then a single `<div class="task-row d-flex flex-wrap justify-content-between align-items-start gap-3">` block ending at line 102, then `<% end %>` at line 103.

Cut that entire `<div class="task-row ...">` … `</div>` block — lines 53 through 102, unchanged, not a rewrite — into a new file `app/views/tasks/_my_task_entry.html.erb`. It already refers to a local named `task`, so it needs no edits.

- [ ] **Step 5: Render parents and their subtasks through that partial**

Replace the now-empty loop body in `my_tasks.html.erb` with:

```erb
      <% @tasks.each do |task| %>
        <%= render "tasks/my_task_entry", task: task %>
        <% task.subtasks.each do |subtask| %>
          <div class="ms-4 border-start ps-3">
            <%= render "tasks/my_task_entry", task: subtask %>
          </div>
        <% end %>
      <% end %>
```

Both the parent and each subtask now render through the same partial, so every subtask keeps its own start/pause/resume/complete controls and its own live duration.

- [ ] **Step 6: Run the test**

Run: `bin/rails test test/controllers/tasks_my_tasks_test.rb -v`
Expected: 2 runs, 0 failures.

- [ ] **Step 7: Run the whole suite**

Run: `bin/rails test`
Expected: no new failures.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/tasks_controller.rb app/views/tasks test/controllers/tasks_my_tasks_test.rb
git commit -m "feat: nest subtasks under their parent on My Tasks"
```

**PHASE 1 COMPLETE — shippable. Department-wide hour visibility and subtasks are live.**

---

## PHASE 2 — Client → Project → Sprint (Tasks 10–13)

---

### Task 10: Client, Project and Sprint models

**Files:**
- Create: `app/models/client.rb`, `app/models/project.rb`, `app/models/sprint.rb`
- Create: migration via generator
- Create: `test/fixtures/clients.yml`, `test/fixtures/projects.yml`, `test/fixtures/sprints.yml`
- Modify: `app/models/department.rb` (add `has_many :clients`)
- Test: `test/models/sprint_test.rb`

**Interfaces:**
- Produces:
  - `Client`: `name`, `department_id`, `active`, `notes`; `has_many :projects`; scope `.active`.
  - `Project`: `client_id`, `name`, `description`, `status`, `start_date`, `target_end_date`; `has_many :sprints`; `#department`.
  - `Sprint`: `project_id`, `name`, `goal`, `start_date`, `end_date`, `status`; `has_many :tasks`; `#department`; `#progress -> [done, total]`; `#logged_seconds`; scope `.active`.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateClientsProjectsAndSprints
```

Fill it with:

```ruby
class CreateClientsProjectsAndSprints < ActiveRecord::Migration[7.1]
  def change
    create_table :clients do |t|
      t.string :name, null: false
      t.references :department, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end
    add_index :clients, %i[department_id name], unique: true

    create_table :projects do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "planned"
      t.date :start_date
      t.date :target_end_date
      t.timestamps
    end
    add_index :projects, %i[client_id name], unique: true

    create_table :sprints do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :goal
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: "planned"
      t.timestamps
    end
    add_index :sprints, %i[project_id name], unique: true
    add_index :sprints, %i[project_id start_date]
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 2: Write the fixtures**

`test/fixtures/clients.yml`:

```yaml
gnexteriors:
  name: GN Exteriors
  department: web
  active: true
```

`test/fixtures/projects.yml`:

```yaml
crm:
  client: gnexteriors
  name: CRM
  status: active
  start_date: 2026-09-01
```

`test/fixtures/sprints.yml`:

```yaml
crm_week_one:
  project: crm
  name: Week 1
  goal: Auth and contacts
  start_date: 2026-09-01
  end_date: 2026-09-07
  status: active
```

- [ ] **Step 3: Write the failing test**

`test/models/sprint_test.rb`:

```ruby
require "test_helper"

class SprintTest < ActiveSupport::TestCase
  setup { @sprint = sprints(:crm_week_one) }

  test "a sprint reaches its department through project and client" do
    assert_equal departments(:web), @sprint.department
  end

  test "end date must not precede start date" do
    @sprint.end_date = @sprint.start_date - 1.day

    refute @sprint.valid?
    assert_includes @sprint.errors[:end_date], "must be on or after the start date"
  end

  test "sprint name is unique within a project" do
    duplicate = Sprint.new(project: projects(:crm), name: "Week 1",
                           start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 14))

    refute duplicate.valid?
  end

  test "progress counts completed tasks" do
    a = Task.create!(title: "A", priority: "normal", sprint: @sprint, assigned_to: users(:exec_web_a),
                     assigned_by: users(:manager_web), task_type: task_types(:web_build))
    Task.create!(title: "B", priority: "normal", sprint: @sprint, assigned_to: users(:exec_web_a),
                 assigned_by: users(:manager_web), task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { a.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { a.complete! }

    assert_equal [1, 2], @sprint.reload.progress
  end

  test "logged seconds sums the work sessions of the sprint's tasks" do
    task = Task.create!(title: "A", priority: "normal", sprint: @sprint, assigned_to: users(:exec_web_a),
                        assigned_by: users(:manager_web), task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }

    assert_equal 7200, @sprint.reload.logged_seconds
  end

  test "a client's name is unique inside a department but reusable across departments" do
    duplicate = Client.new(name: "GN Exteriors", department: departments(:web))
    refute duplicate.valid?

    other_department = Client.new(name: "GN Exteriors", department: departments(:design))
    assert other_department.valid?
  end
end
```

- [ ] **Step 4: Run it and watch it fail**

Run: `bin/rails test test/models/sprint_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant Sprint`.

- [ ] **Step 5: Write the models**

`app/models/client.rb`:

```ruby
# A customer the department does work for. Clients are department-scoped: the
# same company can appear under Web and under Design as separate rows, because
# each department runs its own engagement.
class Client < ApplicationRecord
  belongs_to :department
  has_many :projects, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :department_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  def to_s = name
end
```

`app/models/project.rb`:

```ruby
# A body of work for one client — "CRM", "Website rebuild". Weekly sprints hang
# off a project, so a multi-week build stays one thing with many cycles.
class Project < ApplicationRecord
  STATUSES = %w[planned active on_hold completed].freeze

  belongs_to :client
  has_many :sprints, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :client_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:name) }

  delegate :department, :department_id, to: :client

  def to_s = name
end
```

`app/models/sprint.rb`:

```ruby
# One delivery cycle of a project, normally a week. Tasks point at a sprint
# optionally, so ad-hoc work that belongs to no sprint keeps working unchanged.
class Sprint < ApplicationRecord
  STATUSES = %w[planned active completed].freeze

  belongs_to :project
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :start_date, :end_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_date_after_start_date

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(start_date: :desc) }
  scope :for_department, ->(department_id) {
    joins(project: :client).where(clients: { department_id: department_id })
  }

  delegate :department, :department_id, :client, to: :project

  def to_s = name

  def progress
    rows = tasks.to_a
    [rows.count { |t| t.status == "completed" }, rows.size]
  end

  def logged_seconds
    TaskWorkSession.where(task_id: tasks.select(:id)).sum(:duration_seconds)
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be on or after the start date") if end_date < start_date
  end
end
```

In `app/models/department.rb`, add below `has_many :task_types`:

```ruby
  has_many :clients, dependent: :restrict_with_error
```

- [ ] **Step 6: Run the test**

Run: `bin/rails test test/models/sprint_test.rb -v`
Expected: FAIL on the two tests that set `sprint:` on a Task — `Task` has no `sprint` association yet. That is Task 11. The other four must pass.

- [ ] **Step 7: Commit**

```bash
git add app/models db/migrate db/schema.rb test/fixtures test/models/sprint_test.rb
git commit -m "feat: add Client, Project and Sprint models"
```

---

### Task 11: Attach tasks to sprints, with subtask inheritance

**Files:**
- Create: migration via generator
- Modify: `app/models/task.rb`
- Test: `test/models/task_sprint_test.rb`

**Interfaces:**
- Consumes: `Sprint` (Task 10).
- Produces: `Task#sprint` (optional), scope `Task.in_sprint(id)`, validation `sprint_belongs_to_same_department`, callback `inherit_sprint_from_parent`.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddSprintToTasks
```

```ruby
class AddSprintToTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :tasks, :sprint, foreign_key: true, null: true
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 2: Write the failing test**

`test/models/task_sprint_test.rb`:

```ruby
require "test_helper"

class TaskSprintTest < ActiveSupport::TestCase
  setup { @sprint = sprints(:crm_week_one) }

  def build_task(**overrides)
    Task.new({ title: "T", priority: "normal", assigned_to: users(:exec_web_a),
               assigned_by: users(:manager_web), task_type: task_types(:web_build) }.merge(overrides))
  end

  test "a task can belong to a sprint in its own department" do
    task = build_task(sprint: @sprint)

    assert task.save, task.errors.full_messages.to_sentence
    assert_equal @sprint, task.sprint
  end

  test "a task cannot belong to another department's sprint" do
    design_client = Client.create!(name: "Other", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")
    foreign = Sprint.create!(project: design_project, name: "W1",
                             start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    task = build_task(sprint: foreign)

    refute task.valid?
    assert_includes task.errors[:sprint], "must belong to your department"
  end

  test "a subtask inherits its parent's sprint on save" do
    parent = build_task(sprint: @sprint)
    parent.save!

    child = build_task(parent: parent, title: "Child")
    child.save!

    assert_equal @sprint.id, child.sprint_id
  end

  test "a subtask's sprint follows the parent even if set to something else" do
    parent = build_task(sprint: @sprint)
    parent.save!
    other = Sprint.create!(project: projects(:crm), name: "Week 2",
                           start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 14))

    child = build_task(parent: parent, sprint: other, title: "Child")
    child.save!

    assert_equal @sprint.id, child.sprint_id
  end

  test "in_sprint scope filters by sprint" do
    build_task(sprint: @sprint).save!
    build_task(title: "No sprint").save!

    assert_equal 1, Task.in_sprint(@sprint.id).count
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

Run: `bin/rails test test/models/task_sprint_test.rb -v`
Expected: FAIL — `unknown attribute 'sprint'` or association missing.

- [ ] **Step 4: Implement**

In `app/models/task.rb`, add to the associations:

```ruby
  belongs_to :sprint, optional: true
```

Add to the scopes:

```ruby
  scope :in_sprint, ->(sprint_id) { where(sprint_id: sprint_id) }
```

Add to the validations and callbacks:

```ruby
  before_validation :inherit_sprint_from_parent
  validate :sprint_belongs_to_same_department
```

Add the private methods:

```ruby
  # A subtask always sits in the same sprint as its parent — allowing a split
  # would make sprint hour totals depend on which half of a pair you looked at.
  def inherit_sprint_from_parent
    self.sprint_id = parent.sprint_id if parent.present?
  end

  def sprint_belongs_to_same_department
    return if sprint.blank? || assigned_by.blank?

    unless sprint.department_id == assigned_by.department_id
      errors.add(:sprint, "must belong to your department")
    end
  end
```

- [ ] **Step 5: Run both sprint test files**

Run: `bin/rails test test/models/task_sprint_test.rb test/models/sprint_test.rb -v`
Expected: 5 + 6 runs, 0 failures. The two `sprint_test.rb` tests that failed in Task 10 now pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/task.rb db/migrate db/schema.rb test/models/task_sprint_test.rb
git commit -m "feat: attach tasks to sprints, subtasks inherit the parent's sprint"
```

---

### Task 12: Sprint, project and client management endpoints

**Files:**
- Create: `app/controllers/sprints_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/sprints_controller_test.rb`

**Interfaces:**
- Produces: routes `clients_path` (POST), `projects_path` (POST), `sprints_path` (POST), `sprint_path` (PATCH), `carry_over_sprint_path` (POST). All redirect back to `dashboard_tasks_path(tab: "sprints")`.

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, directly after the `resources :tasks` block:

```ruby
resources :clients, only: [:create]
resources :projects, only: [:create]
resources :sprints, only: [:create, :update] do
  member do
    post :carry_over
  end
end
```

- [ ] **Step 2: Write the failing test**

`test/controllers/sprints_controller_test.rb`:

```ruby
require "test_helper"

class SprintsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "creates a client in the manager's department" do
    assert_difference -> { Client.count }, 1 do
      post clients_path, params: { client: { name: "New Client" } }
    end

    assert_equal departments(:web).id, Client.order(:id).last.department_id
  end

  test "creates a sprint under a project in the manager's department" do
    assert_difference -> { Sprint.count }, 1 do
      post sprints_path, params: { sprint: { project_id: projects(:crm).id, name: "Week 2",
                                             start_date: "2026-09-08", end_date: "2026-09-14" } }
    end
  end

  test "refuses to create a sprint under another department's project" do
    design_client = Client.create!(name: "Other", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")

    assert_no_difference -> { Sprint.count } do
      post sprints_path, params: { sprint: { project_id: design_project.id, name: "W1",
                                             start_date: "2026-09-08", end_date: "2026-09-14" } }
    end
  end

  test "carry over moves unfinished tasks to the target sprint and leaves completed ones" do
    target = Sprint.create!(project: projects(:crm), name: "Week 2",
                            start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 9, 14))
    open_task = Task.create!(title: "Still open", priority: "normal", sprint: sprints(:crm_week_one),
                             assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))
    done_task = Task.create!(title: "Done", priority: "normal", sprint: sprints(:crm_week_one),
                             assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))
    travel_to(Time.zone.parse("2026-09-01 09:00")) { done_task.start! }
    travel_to(Time.zone.parse("2026-09-01 10:00")) { done_task.complete! }

    post carry_over_sprint_path(sprints(:crm_week_one)), params: { target_sprint_id: target.id }

    assert_equal target.id, open_task.reload.sprint_id
    assert_equal sprints(:crm_week_one).id, done_task.reload.sprint_id
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

Run: `bin/rails test test/controllers/sprints_controller_test.rb -v`
Expected: FAIL — `uninitialized constant SprintsController`.

- [ ] **Step 4: Write the controller**

`app/controllers/sprints_controller.rb`:

```ruby
# Client / project / sprint management for a department's Task Manager. Every
# action redirects back to the Sprints tab of the task dashboard — this module
# has no pages of its own.
class SprintsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_department_task_manager
  before_action -> { authorize_page!("task_manager") }

  def create
    project = department_projects.find_by(id: params.dig(:sprint, :project_id))
    return back_with(alert: "Unknown project.") if project.nil?

    sprint = project.sprints.new(sprint_params)
    if sprint.save
      back_with(notice: "Sprint created.")
    else
      back_with(alert: sprint.errors.full_messages.to_sentence)
    end
  end

  def update
    sprint = department_sprints.find_by(id: params[:id])
    return back_with(alert: "Unknown sprint.") if sprint.nil?

    if sprint.update(sprint_params)
      back_with(notice: "Sprint updated.")
    else
      back_with(alert: sprint.errors.full_messages.to_sentence)
    end
  end

  # Unfinished work does not disappear at the end of a cycle — it moves to the
  # next one, the way a Jira sprint closes.
  def carry_over
    sprint = department_sprints.find_by(id: params[:id])
    target = department_sprints.find_by(id: params[:target_sprint_id])
    return back_with(alert: "Unknown sprint.") if sprint.nil? || target.nil?

    moved = sprint.tasks.where.not(status: "completed").update_all(sprint_id: target.id)
    back_with(notice: "Moved #{moved} task(s) to #{target.name}.")
  end

  private

  def department_projects
    Project.joins(:client).where(clients: { department_id: current_user.department_id })
  end

  def department_sprints
    Sprint.for_department(current_user.department_id)
  end

  def sprint_params
    params.require(:sprint).permit(:name, :goal, :start_date, :end_date, :status)
  end

  def back_with(**flash_opts)
    redirect_to dashboard_tasks_path(tab: "sprints"), **flash_opts
  end

  def require_department_task_manager
    return if current_user.org_department&.task_manager_enabled?

    redirect_to root_path, alert: "Task Manager isn't enabled for your department."
  end
end
```

Create `app/controllers/clients_controller.rb`:

```ruby
class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("task_manager") }

  def create
    client = Client.new(client_params.merge(department_id: current_user.department_id))

    if client.save
      redirect_to dashboard_tasks_path(tab: "sprints"), notice: "Client created."
    else
      redirect_to dashboard_tasks_path(tab: "sprints"), alert: client.errors.full_messages.to_sentence
    end
  end

  private

  def client_params
    params.require(:client).permit(:name, :notes, :active)
  end
end
```

Create `app/controllers/projects_controller.rb`:

```ruby
class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("task_manager") }

  def create
    client = Client.where(department_id: current_user.department_id)
                   .find_by(id: params.dig(:project, :client_id))
    return redirect_to(dashboard_tasks_path(tab: "sprints"), alert: "Unknown client.") if client.nil?

    project = client.projects.new(project_params)
    if project.save
      redirect_to dashboard_tasks_path(tab: "sprints"), notice: "Project created."
    else
      redirect_to dashboard_tasks_path(tab: "sprints"), alert: project.errors.full_messages.to_sentence
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :status, :start_date, :target_end_date)
  end
end
```

- [ ] **Step 5: Run the test**

Run: `bin/rails test test/controllers/sprints_controller_test.rb -v`
Expected: 4 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers config/routes.rb test/controllers/sprints_controller_test.rb
git commit -m "feat: add client, project and sprint management endpoints"
```

---

### Task 13: Sprints tab and sprint filter

**Files:**
- Create: `app/views/tasks/_tab_sprints.html.erb`, `app/views/tasks/_sprint_modal.html.erb`
- Modify: `app/controllers/tasks_controller.rb` (`dashboard`, `task_params`), `app/views/tasks/dashboard.html.erb`, `app/views/tasks/_tab_tasks.html.erb`
- Test: `test/controllers/tasks_sprints_tab_test.rb`

**Interfaces:**
- Consumes: `Sprint.for_department`, `Sprint#progress`, `Sprint#logged_seconds` (Task 10); `Task.in_sprint` (Task 11).
- Produces: ivars `@clients`, `@sprints`, `@selected_sprint`.

- [ ] **Step 1: Write the failing test**

`test/controllers/tasks_sprints_tab_test.rb`:

```ruby
require "test_helper"

class TasksSprintsTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "sprints tab lists the department's sprints with progress" do
    get dashboard_tasks_path(tab: "sprints")

    assert_response :success
    assert_includes response.body, "GN Exteriors"
    assert_includes response.body, "Week 1"
  end

  test "sprints tab hides another department's sprints" do
    design_client = Client.create!(name: "Hidden Client", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "Hidden Project")
    Sprint.create!(project: design_project, name: "Hidden Sprint",
                   start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    get dashboard_tasks_path(tab: "sprints")

    refute_includes response.body, "Hidden Sprint"
  end

  test "sprint_id filters the tasks tab" do
    in_sprint = Task.create!(title: "Sprint work", priority: "normal", sprint: sprints(:crm_week_one),
                             assigned_to: users(:exec_web_a), assigned_by: users(:manager_web),
                             task_type: task_types(:web_build))

    get dashboard_tasks_path(sprint_id: sprints(:crm_week_one).id)

    assert_includes response.body, in_sprint.title
    refute_includes response.body, tasks(:pending_a).title
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/tasks_sprints_tab_test.rb -v`
Expected: FAIL — the sprints tab markup does not exist.

- [ ] **Step 3: Load the sprint data in the dashboard action**

In `app/controllers/tasks_controller.rb`, inside `dashboard`, add after the `@task_types` line:

```ruby
    @clients = Client.where(department_id: current_user.department_id).includes(projects: :sprints).ordered
    @sprints = Sprint.for_department(current_user.department_id).includes(project: :client).ordered
    @selected_sprint = @sprints.detect { |s| s.id.to_s == params[:sprint_id].to_s }
```

and add the sprint filter to the `@tasks` chain, directly after the `executive_id` filter:

```ruby
    @tasks = @tasks.in_sprint(params[:sprint_id]) if params[:sprint_id].present?
```

Add `:sprint_id` to the permitted keys in `task_params`:

```ruby
    params.require(:task).permit(:title, :description, :priority, :due_date, :assigned_to_id,
                                 :task_type_id, :custom_sla_minutes, :new_task_type_name,
                                 :parent_id, :sprint_id)
```

- [ ] **Step 4: Build the Sprints tab**

Create `app/views/tasks/_tab_sprints.html.erb`:

```erb
<div class="task-panel-dark">
  <div class="task-panel-dark__header">
    <h3 class="task-panel-dark__title">Sprints</h3>
    <div class="task-panel-dark__controls">
      <button type="button" class="btn btn-outline-premium btn-premium btn-sm"
              data-bs-toggle="modal" data-bs-target="#newClientModal">New Client</button>
      <button type="button" class="btn btn-outline-premium btn-premium btn-sm"
              data-bs-toggle="modal" data-bs-target="#newProjectModal">New Project</button>
      <button type="button" class="btn btn-primary btn-premium btn-sm"
              data-bs-toggle="modal" data-bs-target="#newSprintModal">New Sprint</button>
    </div>
  </div>

  <div class="task-panel-dark__body">
    <% if @sprints.empty? %>
      <div class="task-empty-state">
        <i class="fa-solid fa-flag-checkered"></i>
        <p>No sprints yet — create a client, then a project, then its first weekly sprint.</p>
      </div>
    <% else %>
      <% @sprints.group_by { |s| s.project.client }.each do |client, client_sprints| %>
        <h6 class="fw-bold mt-3 mb-2"><%= client.name %></h6>
        <% client_sprints.group_by(&:project).each do |project, project_sprints| %>
          <div class="text-muted small mb-2"><%= project.name %></div>
          <div class="table-responsive mb-3">
            <table class="table align-middle mb-0 task-table">
              <thead>
                <tr>
                  <th>Sprint</th><th>Dates</th><th>Status</th><th>Progress</th><th>Hours logged</th><th></th>
                </tr>
              </thead>
              <tbody>
                <% project_sprints.each do |sprint| %>
                  <% done, total = sprint.progress %>
                  <tr>
                    <td class="fw-semibold"><%= sprint.name %><div class="text-muted small"><%= sprint.goal %></div></td>
                    <td><%= sprint.start_date.strftime("%d %b") %> – <%= sprint.end_date.strftime("%d %b %Y") %></td>
                    <td><span class="status-tag status-tag--<%= sprint.status %>"><%= sprint.status.humanize %></span></td>
                    <td><%= done %>/<%= total %></td>
                    <td><%= hours_label(sprint.logged_seconds) %></td>
                    <td class="text-end">
                      <%= link_to "View tasks", dashboard_tasks_path(sprint_id: sprint.id),
                            class: "btn btn-outline-premium btn-premium btn-sm" %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      <% end %>
    <% end %>
  </div>
</div>
```

Create `app/views/tasks/_sprint_modal.html.erb`:

```erb
<%
  project_options = @clients.flat_map { |client| client.projects.map { |p| ["#{client.name} — #{p.name}", p.id] } }
%>

<div class="modal fade" id="newClientModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <%= form_with url: clients_path, method: :post, local: true do %>
        <div class="modal-header">
          <h5 class="modal-title fw-bold"><i class="fa-solid fa-building me-2 text-primary"></i>New Client</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <%= label_tag "client[name]", "Client name", class: "form-label" %>
            <%= text_field_tag "client[name]", nil, class: "form-control", required: true %>
          </div>
          <div class="mb-3">
            <%= label_tag "client[notes]", "Notes", class: "form-label" %>
            <%= text_area_tag "client[notes]", nil, class: "form-control", rows: 2 %>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-premium btn-premium" data-bs-dismiss="modal">Cancel</button>
          <%= submit_tag "Create Client", class: "btn btn-primary btn-premium" %>
        </div>
      <% end %>
    </div>
  </div>
</div>

<div class="modal fade" id="newProjectModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <%= form_with url: projects_path, method: :post, local: true do %>
        <div class="modal-header">
          <h5 class="modal-title fw-bold"><i class="fa-solid fa-diagram-project me-2 text-primary"></i>New Project</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <%= label_tag "project[client_id]", "Client", class: "form-label" %>
            <%= select_tag "project[client_id]",
                  options_for_select(@clients.map { |c| [c.name, c.id] }),
                  class: "form-select", required: true %>
          </div>
          <div class="mb-3">
            <%= label_tag "project[name]", "Project name", class: "form-label" %>
            <%= text_field_tag "project[name]", nil, class: "form-control", required: true,
                  placeholder: "CRM" %>
          </div>
          <div class="mb-3">
            <%= label_tag "project[status]", "Status", class: "form-label" %>
            <%= select_tag "project[status]",
                  options_for_select(Project::STATUSES.map { |st| [st.humanize, st] }, "active"),
                  class: "form-select" %>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-premium btn-premium" data-bs-dismiss="modal">Cancel</button>
          <%= submit_tag "Create Project", class: "btn btn-primary btn-premium" %>
        </div>
      <% end %>
    </div>
  </div>
</div>

<div class="modal fade" id="newSprintModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <%= form_with url: sprints_path, method: :post, local: true do %>
        <div class="modal-header">
          <h5 class="modal-title fw-bold"><i class="fa-solid fa-flag-checkered me-2 text-primary"></i>New Sprint</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <%= label_tag "sprint[project_id]", "Project", class: "form-label" %>
            <%= select_tag "sprint[project_id]", options_for_select(project_options),
                  class: "form-select", required: true %>
          </div>
          <div class="mb-3">
            <%= label_tag "sprint[name]", "Sprint name", class: "form-label" %>
            <%= text_field_tag "sprint[name]", nil, class: "form-control", required: true,
                  placeholder: "Week 1" %>
          </div>
          <div class="mb-3">
            <%= label_tag "sprint[goal]", "Goal", class: "form-label" %>
            <%= text_area_tag "sprint[goal]", nil, class: "form-control", rows: 2 %>
          </div>
          <div class="row g-2">
            <div class="col-6 mb-3">
              <%= label_tag "sprint[start_date]", "Starts", class: "form-label" %>
              <%= date_field_tag "sprint[start_date]", Date.current.beginning_of_week,
                    class: "form-control", required: true %>
            </div>
            <div class="col-6 mb-3">
              <%= label_tag "sprint[end_date]", "Ends", class: "form-label" %>
              <%= date_field_tag "sprint[end_date]", Date.current.end_of_week,
                    class: "form-control", required: true %>
            </div>
          </div>
          <div class="mb-3">
            <%= label_tag "sprint[status]", "Status", class: "form-label" %>
            <%= select_tag "sprint[status]",
                  options_for_select(Sprint::STATUSES.map { |st| [st.humanize, st] }, "active"),
                  class: "form-select" %>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-premium btn-premium" data-bs-dismiss="modal">Cancel</button>
          <%= submit_tag "Create Sprint", class: "btn btn-primary btn-premium" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

The dates default to the current week, so creating a weekly sprint is one click.

- [ ] **Step 5: Add the tab and the sprint filter pill**

In `app/views/tasks/dashboard.html.erb`, add a third `<li>` to the tab list:

```erb
  <li class="nav-item">
    <button class="nav-link <%= 'active' if params[:tab] == 'sprints' %>"
            data-bs-toggle="tab" data-bs-target="#tab-sprints" type="button">Sprints</button>
  </li>
```

and a third pane:

```erb
  <div class="tab-pane fade <%= 'show active' if params[:tab] == 'sprints' %>" id="tab-sprints">
    <%= render "tasks/tab_sprints" %>
  </div>
```

Render the modals once at the bottom of `dashboard.html.erb`, beside the existing `newTaskModal`:

```erb
<%= render "tasks/sprint_modal" %>
```

In `_tab_tasks.html.erb`, add a sprint select beside the executive select:

```erb
        <%= select_tag :sprint_id,
              options_for_select([["All sprints", ""]] + @sprints.map { |s| ["#{s.project.client.name} · #{s.project.name} · #{s.name}", s.id] }, params[:sprint_id]),
              class: "task-panel-dark__exec-select", onchange: "this.form.submit()" %>
```

- [ ] **Step 6: Run the test**

Run: `bin/rails test test/controllers/tasks_sprints_tab_test.rb -v`
Expected: 3 runs, 0 failures.

- [ ] **Step 7: Run the whole suite**

Run: `bin/rails test`
Expected: no new failures.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/tasks_controller.rb app/views/tasks test/controllers/tasks_sprints_tab_test.rb
git commit -m "feat: add Sprints tab and sprint filtering to the task dashboard"
```

**PHASE 2 COMPLETE — shippable. Client/project/sprint structure is live.**

---

## PHASE 3 — CSV import and exports (Tasks 14–16)

---

### Task 14: CSV importer — parse and validate (dry run)

**Files:**
- Create: `app/services/task_csv_importer.rb`
- Test: `test/services/task_csv_importer_test.rb`
- Create: `test/fixtures/files/sprint_tasks.csv`

**Interfaces:**
- Produces:
  - `TaskCsvImporter.new(csv_text:, manager:, sprint:, create_missing_types: false)`
  - `#rows -> Array<TaskCsvImporter::Row>` where
    `Row = Struct.new(:line, :key, :title, :description, :parent_key, :assignee_email, :type_name, :priority, :due_date, :sla_minutes, :assignee, :task_type, :errors, keyword_init: true)`
  - `#valid? -> Boolean`
  - `#error_count -> Integer`
  - `HEADERS -> Array<String>`
  - `MAX_ROWS = 1000`

- [ ] **Step 1: Write the fixture file**

`test/fixtures/files/sprint_tasks.csv`:

```csv
Key,Title,Description,Parent,Assignee Email,Task Type,Priority,Due Date,SLA Minutes
T1,Build login,Auth screens,,exec.web.a@example.com,Build,urgent,2026-09-05,180
T2,Password reset,,T1,exec.web.b@example.com,Build,normal,2026-09-06,60
T3,Contacts list,,,exec.web.a@example.com,Fix,normal,,30
```

- [ ] **Step 2: Write the failing test**

`test/services/task_csv_importer_test.rb`:

```ruby
require "test_helper"

class TaskCsvImporterTest < ActiveSupport::TestCase
  setup do
    @manager = users(:manager_web)
    @sprint = sprints(:crm_week_one)
  end

  def importer(csv, **opts)
    TaskCsvImporter.new(csv_text: csv, manager: @manager, sprint: @sprint, **opts)
  end

  def valid_csv = file_fixture("sprint_tasks.csv").read

  test "parses every data row" do
    result = importer(valid_csv)

    assert_equal 3, result.rows.size
    assert result.valid?, result.rows.flat_map(&:errors).inspect
  end

  test "resolves a parent by its Key" do
    result = importer(valid_csv)

    child = result.rows.find { |r| r.key == "T2" }
    assert_equal "T1", child.parent_key
  end

  test "rejects an assignee outside the manager's department" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,X,exec.design@example.com,Build\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "not an Executive in your department"
  end

  test "rejects an unknown task type unless creation is allowed" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,X,exec.web.a@example.com,Nonexistent\n"

    refute importer(csv).valid?
    assert importer(csv, create_missing_types: true).valid?
  end

  test "rejects a parent key that no row defines" do
    csv = "Key,Title,Parent,Assignee Email,Task Type\nT1,X,GHOST,exec.web.a@example.com,Build\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "no row defines parent key"
  end

  test "rejects a subtask whose parent is itself a subtask" do
    csv = <<~CSV
      Key,Title,Parent,Assignee Email,Task Type
      T1,Top,,exec.web.a@example.com,Build
      T2,Child,T1,exec.web.a@example.com,Build
      T3,Grandchild,T2,exec.web.a@example.com,Build
    CSV

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.last.errors.join, "only one level of subtasks"
  end

  test "rejects a missing title" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,,exec.web.a@example.com,Build\n"

    refute importer(csv).valid?
  end

  test "rejects an invalid priority" do
    csv = "Key,Title,Assignee Email,Task Type,Priority\nT1,X,exec.web.a@example.com,Build,critical\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "priority must be"
  end

  test "accepts both date formats and a blank date" do
    csv = <<~CSV
      Key,Title,Assignee Email,Task Type,Due Date
      T1,A,exec.web.a@example.com,Build,2026-09-05
      T2,B,exec.web.a@example.com,Build,06/09/2026
      T3,C,exec.web.a@example.com,Build,
    CSV

    result = importer(csv)

    assert result.valid?, result.rows.flat_map(&:errors).inspect
    assert_equal Date.new(2026, 9, 5), result.rows[0].due_date
    assert_equal Date.new(2026, 9, 6), result.rows[1].due_date
    assert_nil result.rows[2].due_date
  end

  test "rejects a file over the row cap" do
    body = (1..1001).map { |i| "T#{i},Task #{i},exec.web.a@example.com,Build" }.join("\n")
    csv = "Key,Title,Assignee Email,Task Type\n#{body}\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "1000 rows"
  end

  test "rejects a file missing the Title column" do
    csv = "Key,Assignee Email,Task Type\nT1,exec.web.a@example.com,Build\n"

    result = importer(csv)

    refute result.valid?
    assert_includes result.rows.first.errors.join, "Title"
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

Run: `bin/rails test test/services/task_csv_importer_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant TaskCsvImporter`.

- [ ] **Step 4: Write the importer**

`app/services/task_csv_importer.rb`:

```ruby
require "csv"

# Parses a Jira/ClickUp-shaped CSV into validated rows, then (in commit!) turns
# them into tasks and subtasks inside one transaction.
#
# Two passes: parse each line, then resolve Parent references against the Key
# column so a parent may appear anywhere in the file, before or after its
# children.
class TaskCsvImporter
  MAX_ROWS = 1000
  REQUIRED_HEADERS = ["Title", "Assignee Email", "Task Type"].freeze
  HEADERS = ["Key", "Title", "Description", "Parent", "Assignee Email",
             "Task Type", "Priority", "Due Date", "SLA Minutes"].freeze

  Row = Struct.new(:line, :key, :title, :description, :parent_key, :assignee_email,
                   :type_name, :priority, :due_date, :sla_minutes, :assignee,
                   :task_type, :errors, keyword_init: true)

  def initialize(csv_text:, manager:, sprint: nil, create_missing_types: false)
    @csv_text = csv_text.to_s
    @manager = manager
    @sprint = sprint
    @create_missing_types = create_missing_types
  end

  def rows
    @rows ||= parse
  end

  def valid? = rows.any? && rows.all? { |r| r.errors.empty? }

  def error_count = rows.count { |r| r.errors.any? }

  private

  def parse
    table = begin
      CSV.parse(@csv_text, headers: true)
    rescue CSV::MalformedCSVError => e
      return [fatal("The file could not be read as CSV: #{e.message}")]
    end

    missing = REQUIRED_HEADERS - (table.headers || []).compact.map(&:strip)
    return [fatal("The file is missing required column(s): #{missing.join(', ')}.")] if missing.any?
    return [fatal("The file has #{table.size} rows; the limit is #{MAX_ROWS} rows.")] if table.size > MAX_ROWS
    return [fatal("The file has no data rows.")] if table.size.zero?

    parsed = table.each_with_index.map { |csv_row, index| build_row(csv_row, index + 2) }
    validate_parents(parsed)
    parsed
  end

  def fatal(message)
    Row.new(line: 1, errors: [message])
  end

  def build_row(csv_row, line)
    row = Row.new(
      line: line,
      key: value(csv_row, "Key"),
      title: value(csv_row, "Title"),
      description: value(csv_row, "Description"),
      parent_key: value(csv_row, "Parent"),
      assignee_email: value(csv_row, "Assignee Email"),
      type_name: value(csv_row, "Task Type"),
      priority: value(csv_row, "Priority").presence&.downcase || "normal",
      sla_minutes: value(csv_row, "SLA Minutes").presence,
      errors: []
    )

    row.errors << "title is required" if row.title.blank?
    unless Task::PRIORITIES.include?(row.priority)
      row.errors << "priority must be one of #{Task::PRIORITIES.join(', ')}"
    end

    resolve_assignee(row)
    resolve_task_type(row)
    resolve_due_date(row, value(csv_row, "Due Date"))
    row
  end

  def value(csv_row, header)
    csv_row[header].to_s.strip
  end

  def resolve_assignee(row)
    return row.errors << "assignee email is required" if row.assignee_email.blank?

    row.assignee = department_executives[row.assignee_email.downcase]
    return if row.assignee

    row.errors << "#{row.assignee_email} is not an Executive in your department"
  end

  def department_executives
    @department_executives ||= User.employed.joins(:access_role)
                                   .where(department_id: @manager.department_id, roles: { name: "Executive" })
                                   .index_by { |u| u.email.to_s.downcase }
  end

  def resolve_task_type(row)
    return row.errors << "task type is required" if row.type_name.blank?

    row.task_type = task_types[row.type_name.downcase]
    return if row.task_type
    return if @create_missing_types

    row.errors << "task type '#{row.type_name}' does not exist in your department"
  end

  def task_types
    @task_types ||= TaskType.where(department_id: @manager.department_id)
                            .index_by { |t| t.name.to_s.downcase }
  end

  def resolve_due_date(row, raw)
    return if raw.blank?

    row.due_date = Date.strptime(raw, "%Y-%m-%d") rescue nil
    row.due_date ||= (Date.strptime(raw, "%d/%m/%Y") rescue nil)
    row.errors << "due date '#{raw}' is not YYYY-MM-DD or DD/MM/YYYY" if row.due_date.nil?
  end

  # Parents resolve after every line is parsed, so a child may precede its
  # parent in the file — which Jira exports routinely do.
  def validate_parents(parsed)
    by_key = parsed.reject { |r| r.key.blank? }.index_by(&:key)

    parsed.each do |row|
      next if row.parent_key.blank?

      parent = by_key[row.parent_key]
      if parent.nil?
        row.errors << "no row defines parent key '#{row.parent_key}'"
      elsif parent.parent_key.present?
        row.errors << "only one level of subtasks is allowed"
      end
    end
  end
end
```

- [ ] **Step 5: Run the test**

Run: `bin/rails test test/services/task_csv_importer_test.rb -v`
Expected: 11 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/task_csv_importer.rb test/services test/fixtures/files/sprint_tasks.csv
git commit -m "feat: add CSV importer parsing and validation for sprint tasks"
```

---

### Task 15: CSV import commit and dashboard modal

**Files:**
- Modify: `app/services/task_csv_importer.rb` (add `commit!`)
- Modify: `app/controllers/tasks_controller.rb` (`import_preview`, `import`)
- Modify: `config/routes.rb`
- Create: `app/views/tasks/_import_modal.html.erb`
- Modify: `app/views/tasks/dashboard.html.erb`
- Test: `test/services/task_csv_importer_commit_test.rb`, `test/controllers/tasks_import_test.rb`

**Interfaces:**
- Consumes: `TaskCsvImporter#rows`, `#valid?` (Task 14).
- Produces: `TaskCsvImporter#commit! -> Integer` (tasks created); raises `ActiveRecord::Rollback` on any failure so nothing is written. Routes `import_preview_tasks_path` (POST), `import_tasks_path` (POST).

- [ ] **Step 1: Write the failing test**

`test/services/task_csv_importer_commit_test.rb`:

```ruby
require "test_helper"

class TaskCsvImporterCommitTest < ActiveSupport::TestCase
  setup do
    @manager = users(:manager_web)
    @sprint = sprints(:crm_week_one)
  end

  def importer(csv, **opts)
    TaskCsvImporter.new(csv_text: csv, manager: @manager, sprint: @sprint, **opts)
  end

  test "commit creates tasks and links subtasks to their parent" do
    csv = file_fixture("sprint_tasks.csv").read

    assert_difference -> { Task.count }, 3 do
      assert_equal 3, importer(csv).commit!
    end

    parent = Task.find_by(title: "Build login")
    child = Task.find_by(title: "Password reset")
    assert_equal parent.id, child.parent_id
    assert_equal users(:exec_web_b).id, child.assigned_to_id
    assert_equal @sprint.id, parent.sprint_id
    assert_equal @sprint.id, child.sprint_id
    assert_equal @manager.id, parent.assigned_by_id
    assert_equal "urgent", parent.priority
    assert_equal 180, parent.custom_sla_minutes
  end

  test "commit resolves a parent that appears after its child" do
    csv = <<~CSV
      Key,Title,Parent,Assignee Email,Task Type
      T2,Child first,T1,exec.web.a@example.com,Build
      T1,Parent second,,exec.web.a@example.com,Build
    CSV

    importer(csv).commit!

    assert_equal Task.find_by(title: "Parent second").id,
                 Task.find_by(title: "Child first").parent_id
  end

  test "commit writes nothing when any row is invalid" do
    csv = <<~CSV
      Key,Title,Assignee Email,Task Type
      T1,Good row,exec.web.a@example.com,Build
      T2,Bad row,exec.design@example.com,Build
    CSV

    assert_no_difference -> { Task.count } do
      assert_equal 0, importer(csv).commit!
    end
  end

  test "commit creates a missing task type when allowed" do
    csv = "Key,Title,Assignee Email,Task Type\nT1,X,exec.web.a@example.com,Brand New Type\n"

    assert_difference -> { TaskType.count }, 1 do
      importer(csv, create_missing_types: true).commit!
    end

    assert_equal departments(:web).id, TaskType.find_by(name: "Brand New Type").department_id
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/services/task_csv_importer_commit_test.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'commit!'`.

- [ ] **Step 3: Add commit! to the importer**

Append inside `class TaskCsvImporter`, above `private`:

```ruby
  # All or nothing: a file with any invalid row writes no tasks at all, so a
  # half-imported sprint can never happen.
  def commit!
    return 0 unless valid?

    created = 0
    ActiveRecord::Base.transaction do
      by_key = {}

      # Parents first so a child can always find its parent's id, regardless of
      # the order the rows appeared in the file.
      ordered_rows.each do |row|
        task = Task.create!(
          title: row.title,
          description: row.description.presence,
          priority: row.priority,
          due_date: row.due_date,
          assigned_to_id: row.assignee.id,
          assigned_by_id: @manager.id,
          task_type_id: task_type_for(row).id,
          custom_sla_minutes: row.sla_minutes.presence&.to_i,
          sprint_id: @sprint&.id,
          parent_id: row.parent_key.present? ? by_key.fetch(row.parent_key).id : nil
        )
        by_key[row.key] = task if row.key.present?
        created += 1
      end
    end
    created
  end
```

and these private helpers:

```ruby
  def ordered_rows
    parents, children = rows.partition { |r| r.parent_key.blank? }
    parents + children
  end

  def task_type_for(row)
    return row.task_type if row.task_type

    @created_types ||= {}
    @created_types[row.type_name.downcase] ||= TaskType.create!(
      name: row.type_name,
      department_id: @manager.department_id,
      sla_minutes: row.sla_minutes.presence&.to_i || 0
    )
  end
```

- [ ] **Step 4: Run the commit test**

Run: `bin/rails test test/services/task_csv_importer_commit_test.rb -v`
Expected: 4 runs, 0 failures.

- [ ] **Step 5: Add the routes**

In `config/routes.rb`, inside the `resources :tasks ... collection do` block:

```ruby
    post :import_preview
    post :import
```

- [ ] **Step 6: Write the controller test**

`test/controllers/tasks_import_test.rb`:

```ruby
require "test_helper"

class TasksImportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  def upload
    Rack::Test::UploadedFile.new(file_fixture("sprint_tasks.csv"), "text/csv")
  end

  test "preview reports the rows without creating anything" do
    assert_no_difference -> { Task.count } do
      post import_preview_tasks_path, params: { file: upload, sprint_id: sprints(:crm_week_one).id }
    end

    assert_response :success
    assert_includes response.body, "Build login"
  end

  test "import creates the tasks" do
    assert_difference -> { Task.count }, 3 do
      post import_tasks_path, params: { file: upload, sprint_id: sprints(:crm_week_one).id }
    end

    assert_redirected_to dashboard_tasks_path(tab: "tasks")
  end

  test "import refuses a sprint from another department" do
    design_client = Client.create!(name: "Other", department: departments(:design))
    design_project = Project.create!(client: design_client, name: "P")
    foreign = Sprint.create!(project: design_project, name: "W1",
                             start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 7))

    assert_no_difference -> { Task.count } do
      post import_tasks_path, params: { file: upload, sprint_id: foreign.id }
    end

    assert_equal "That sprint doesn't belong to your department.", flash[:alert]
  end

  test "import rejects a missing file" do
    post import_tasks_path, params: { sprint_id: sprints(:crm_week_one).id }

    assert_redirected_to dashboard_tasks_path(tab: "tasks")
    assert_equal "Choose a CSV file to import.", flash[:alert]
  end
end
```

- [ ] **Step 7: Add the controller actions**

In `app/controllers/tasks_controller.rb`, add `import_preview` and `import` to the `authorize_page!` filter list:

```ruby
  before_action -> { authorize_page!("task_manager") }, only: %i[dashboard new create import_preview import]
```

and add the actions:

```ruby
  def import_preview
    importer, error = build_importer
    return redirect_to(dashboard_tasks_path(tab: "tasks"), alert: error) if importer.nil?

    render partial: "tasks/import_preview", locals: { importer: importer }
  end

  def import
    importer, error = build_importer
    return redirect_to(dashboard_tasks_path(tab: "tasks"), alert: error) if importer.nil?

    if importer.valid?
      created = importer.commit!
      redirect_to dashboard_tasks_path(tab: "tasks"), notice: "Imported #{created} task(s)."
    else
      redirect_to dashboard_tasks_path(tab: "tasks"),
                  alert: "Nothing was imported — #{importer.error_count} row(s) have errors."
    end
  end
```

and the private helper:

```ruby
  # Returns [importer, nil] or [nil, error_message]. A sprint id from another
  # department must never reach the importer, and the manager needs to be told
  # which of the two things went wrong.
  def build_importer
    return [nil, "Choose a CSV file to import."] if params[:file].blank?

    sprint = nil
    if params[:sprint_id].present?
      sprint = Sprint.for_department(current_user.department_id).find_by(id: params[:sprint_id])
      return [nil, "That sprint doesn't belong to your department."] if sprint.nil?
    end

    importer = TaskCsvImporter.new(
      csv_text: params[:file].read,
      manager: current_user,
      sprint: sprint,
      create_missing_types: params[:create_missing_types] == "1"
    )
    [importer, nil]
  end
```

- [ ] **Step 8: Build the import modal and preview partial**

Create `app/views/tasks/_import_modal.html.erb`:

```erb
<div class="modal fade" id="importTasksModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <%= form_with url: import_tasks_path, method: :post, multipart: true, local: true,
                    id: "importTasksForm" do %>
        <div class="modal-header">
          <h5 class="modal-title fw-bold"><i class="fa-solid fa-file-csv me-2 text-primary"></i>Import Tasks from CSV</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <p class="text-muted small">
            Columns: <code>Key, Title, Description, Parent, Assignee Email, Task Type, Priority, Due Date, SLA Minutes</code>.
            Set a subtask's <code>Parent</code> to its parent row's <code>Key</code>. Maximum 1000 rows.
          </p>

          <div class="mb-3">
            <%= label_tag :file, "CSV file", class: "form-label" %>
            <%= file_field_tag :file, accept: ".csv", class: "form-control", required: true %>
          </div>

          <div class="mb-3">
            <%= label_tag :sprint_id, "Add to sprint (optional)", class: "form-label" %>
            <%= select_tag :sprint_id,
                  options_for_select([["No sprint", ""]] + @sprints.map { |sp|
                    ["#{sp.project.client.name} · #{sp.project.name} · #{sp.name}", sp.id]
                  }, params[:sprint_id]),
                  class: "form-select" %>
          </div>

          <div class="form-check mb-3">
            <%= check_box_tag :create_missing_types, "1", false, class: "form-check-input" %>
            <%= label_tag :create_missing_types, "Create task types that don't exist yet",
                  class: "form-check-label" %>
          </div>

          <div id="importPreviewTarget"></div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-outline-premium btn-premium" data-bs-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-outline-premium btn-premium"
                  formaction="<%= import_preview_tasks_path %>" formmethod="post"
                  formtarget="_self">Preview</button>
          <%= submit_tag "Import", class: "btn btn-primary btn-premium" %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

The Preview button reuses the same form via `formaction`, so the file and options
post to `import_preview_tasks_path` and the validated row table renders back. The
Import button posts the same fields to `import_tasks_path`.

Create `app/views/tasks/_import_preview.html.erb`:

```erb
<div class="table-responsive">
  <table class="table table-sm align-middle mb-0">
    <thead><tr><th>Line</th><th>Title</th><th>Assignee</th><th>Parent</th><th>Status</th></tr></thead>
    <tbody>
      <% importer.rows.each do |row| %>
        <tr class="<%= 'table-danger' if row.errors.any? %>">
          <td><%= row.line %></td>
          <td><%= row.title %></td>
          <td><%= row.assignee_email %></td>
          <td><%= row.parent_key.presence || "—" %></td>
          <td><%= row.errors.any? ? row.errors.join("; ") : "OK" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
<p class="mt-3 mb-0 fw-semibold">
  <%= importer.valid? ? "All #{importer.rows.size} row(s) are valid — press Import to commit." : "#{importer.error_count} row(s) have errors. Nothing will be imported until they are fixed." %>
</p>
```

Add an Import button to the header card in `dashboard.html.erb`, beside "New Task":

```erb
    <button type="button" class="btn btn-outline-premium btn-premium" data-bs-toggle="modal" data-bs-target="#importTasksModal">
      <i class="fa-solid fa-file-csv me-2"></i>Import CSV
    </button>
```

and render the modal at the bottom:

```erb
<%= render "tasks/import_modal" %>
```

- [ ] **Step 9: Run the controller test**

Run: `bin/rails test test/controllers/tasks_import_test.rb -v`
Expected: 4 runs, 0 failures.

- [ ] **Step 10: Commit**

```bash
git add app/services app/controllers app/views/tasks config/routes.rb test
git commit -m "feat: import sprint tasks and subtasks from CSV with a dry-run preview"
```

---

### Task 16: Weekly timing and monthly stats exports

**Files:**
- Create: `app/services/task_report_exporter.rb`
- Modify: `app/controllers/tasks_controller.rb` (`export`)
- Modify: `config/routes.rb`
- Test: `test/services/task_report_exporter_test.rb`, `test/controllers/tasks_export_test.rb`

**Interfaces:**
- Consumes: `Reports::ExecutiveHours` (Task 7).
- Produces:
  - `TaskReportExporter.new(department:, range:, tasks: nil)`
  - `#weekly_timing -> [headers, rows]`
  - `#monthly_stats -> [headers, rows]`
  - `#task_list -> [headers, rows]`
  - `#to_csv(report) -> String`
  - `#to_xlsx(report) -> String` (binary)
  - Route `export_tasks_path(report:, format:)`.

- [ ] **Step 1: Write the failing test**

`test/services/task_report_exporter_test.rb`:

```ruby
require "test_helper"

class TaskReportExporterTest < ActiveSupport::TestCase
  setup do
    @range = Time.zone.parse("2026-09-01 00:00")..Time.zone.parse("2026-09-07 23:59:59")
    task = tasks(:pending_a)
    travel_to(Time.zone.parse("2026-09-01 09:00")) { task.start! }
    travel_to(Time.zone.parse("2026-09-01 11:00")) { task.complete! }
    TimeClock.create!(user_id: users(:exec_web_a).id,
                      clock_in: Time.zone.parse("2026-09-01 09:00"),
                      clock_out: Time.zone.parse("2026-09-01 18:00"),
                      total_duration: 28_800, break_duration: 0)
    @exporter = TaskReportExporter.new(department: departments(:web), range: @range)
  end

  test "weekly timing has a row per executive per day with activity" do
    headers, rows = @exporter.weekly_timing

    assert_equal ["Executive", "Date", "Task Hours", "Attendance Hours", "Untracked Hours"], headers
    row = rows.find { |r| r[0] == "Web Exec A" && r[1] == "2026-09-01" }
    assert_equal [2.0, 8.0, 6.0], row[2..4]
  end

  test "monthly stats has one row per executive" do
    headers, rows = @exporter.monthly_stats

    assert_equal ["Executive", "Task Hours", "Attendance Hours", "Untracked Hours",
                  "Tasks Completed", "Over SLA", "Average Task Hours"], headers
    assert_equal 2, rows.size
    row = rows.find { |r| r[0] == "Web Exec A" }
    assert_equal 2.0, row[1]
    assert_equal 1, row[4]
  end

  test "task list exports the tasks it is given" do
    exporter = TaskReportExporter.new(department: departments(:web), range: @range,
                                      tasks: Task.where(id: tasks(:pending_a).id))

    _headers, rows = exporter.task_list

    assert_equal 1, rows.size
    assert_equal tasks(:pending_a).title, rows.first[0]
  end

  test "to_csv renders headers and rows" do
    csv = @exporter.to_csv(@exporter.weekly_timing)

    assert csv.start_with?("Executive,Date,Task Hours")
    assert_includes csv, "Web Exec A,2026-09-01,2.0"
  end

  test "to_xlsx returns a non-empty xlsx package" do
    data = @exporter.to_xlsx(@exporter.monthly_stats)

    assert data.bytesize.positive?
    assert data.start_with?("PK") # xlsx is a zip archive
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/services/task_report_exporter_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant TaskReportExporter`.

- [ ] **Step 3: Write the exporter**

`app/services/task_report_exporter.rb`:

```ruby
require "csv"
require "caxlsx"

# Turns the department hours matrix into the three downloadable reports. Each
# builder returns [headers, rows] so the same data renders as CSV or xlsx.
class TaskReportExporter
  def initialize(department:, range:, tasks: nil)
    @department = department
    @range = range
    @tasks = tasks
  end

  def weekly_timing
    headers = ["Executive", "Date", "Task Hours", "Attendance Hours", "Untracked Hours"]

    rows = report.executives.flat_map do |executive|
      report.dates.filter_map do |date|
        cell = report.for(executive.id, date)
        next if cell[:task_seconds].zero? && cell[:attendance_seconds].zero?

        [executive.name, date.to_s, hours(cell[:task_seconds]),
         hours(cell[:attendance_seconds]), hours(cell[:gap_seconds])]
      end
    end

    [headers, rows]
  end

  def monthly_stats
    headers = ["Executive", "Task Hours", "Attendance Hours", "Untracked Hours",
               "Tasks Completed", "Over SLA", "Average Task Hours"]

    rows = report.executives.map do |executive|
      totals = report.totals_for(executive.id)
      completed = completed_counts[executive.id] || 0
      [executive.name,
       hours(totals[:task_seconds]),
       hours(totals[:attendance_seconds]),
       hours(totals[:gap_seconds]),
       completed,
       over_sla_counts[executive.id] || 0,
       completed.zero? ? 0.0 : hours(totals[:task_seconds] / completed)]
    end

    [headers, rows]
  end

  def task_list
    headers = ["Title", "Sprint", "Executive", "Type", "Status", "Priority",
               "Due Date", "Hours Logged", "Over SLA", "Parent"]

    scope = (@tasks || Task.none).includes(:assigned_to, :task_type, :parent, sprint: { project: :client })
    rows = scope.map do |task|
      [task.title,
       task.sprint&.name,
       task.assigned_to&.name,
       task.task_type&.name,
       task.status,
       task.priority,
       task.due_date&.to_s,
       hours(task.live_duration_seconds),
       task.over_sla? ? "Yes" : "No",
       task.parent&.title]
    end

    [headers, rows]
  end

  def to_csv(report_data)
    headers, rows = report_data
    CSV.generate do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end

  def to_xlsx(report_data)
    headers, rows = report_data
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Report") do |sheet|
      sheet.add_row headers
      rows.each { |row| sheet.add_row row }
    end
    package.to_stream.read
  end

  private

  def report
    @report ||= Reports::ExecutiveHours.new(department: @department, range: @range)
  end

  def hours(seconds) = (seconds.to_i / 3600.0).round(2)

  def completed_counts
    @completed_counts ||= Task.where(assigned_to_id: report.executives.map(&:id),
                                     status: "completed", ended_at: @range)
                              .group(:assigned_to_id).count
  end

  def over_sla_counts
    @over_sla_counts ||= Task.where(assigned_to_id: report.executives.map(&:id),
                                    status: "completed", over_sla: true, ended_at: @range)
                             .group(:assigned_to_id).count
  end
end
```

- [ ] **Step 4: Run the exporter test**

Run: `bin/rails test test/services/task_report_exporter_test.rb -v`
Expected: 5 runs, 0 failures.

- [ ] **Step 5: Add the route**

In `config/routes.rb`, inside the tasks `collection` block:

```ruby
    get :export
```

- [ ] **Step 6: Write the controller test**

`test/controllers/tasks_export_test.rb`:

```ruby
require "test_helper"

class TasksExportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:manager_web) }

  test "weekly timing downloads as csv" do
    get export_tasks_path(report: "weekly_timing", format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Executive,Date,Task Hours"
  end

  test "monthly stats downloads as xlsx" do
    get export_tasks_path(report: "monthly_stats", format: :xlsx)

    assert_response :success
    assert response.body.start_with?("PK")
  end

  test "an unknown report name is rejected" do
    get export_tasks_path(report: "everything", format: :csv)

    assert_redirected_to dashboard_tasks_path
  end

  test "the task list export only contains this department's tasks" do
    design_manager = User.create!(email: "dm@example.com", password: "password123", name: "DM",
                                  role_id: roles(:manager).id, department_id: departments(:design).id,
                                  employeed: true)
    Task.create!(title: "Design only task", priority: "normal", assigned_to: users(:exec_design),
                 assigned_by: design_manager,
                 task_type: TaskType.create!(name: "X", department: departments(:design), sla_minutes: 5))

    get export_tasks_path(report: "task_list", format: :csv)

    refute_includes response.body, "Design only task"
  end
end
```

- [ ] **Step 7: Add the export action**

In `app/controllers/tasks_controller.rb`, add `:export` to the `authorize_page!` filter list, then add:

```ruby
  REPORTS = %w[weekly_timing monthly_stats task_list].freeze

  def export
    report_name = params[:report].to_s
    return redirect_to(dashboard_tasks_path, alert: "Unknown report.") unless REPORTS.include?(report_name)

    @period = params[:period] == "month" ? "month" : "week"
    @week_start = parse_week_start

    exporter = TaskReportExporter.new(
      department: current_user.org_department,
      range: hours_range,
      tasks: department_tasks
    )
    data = exporter.public_send(report_name)
    stamp = Date.current.strftime("%Y%m%d")

    if params[:format].to_s == "xlsx"
      send_data exporter.to_xlsx(data), filename: "#{report_name}_#{stamp}.xlsx",
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    else
      send_data exporter.to_csv(data), filename: "#{report_name}_#{stamp}.csv", type: "text/csv"
    end
  end
```

- [ ] **Step 8: Add export buttons to the Team Hours tab**

In `app/views/tasks/_tab_team_hours.html.erb`, add inside `task-panel-dark__controls`:

```erb
      <%= link_to "CSV", export_tasks_path(report: "weekly_timing", format: :csv, period: @period, week_start: @week_start),
            class: "btn btn-outline-premium btn-premium btn-sm" %>
      <%= link_to "Excel", export_tasks_path(report: "monthly_stats", format: :xlsx, period: @period, week_start: @week_start),
            class: "btn btn-outline-premium btn-premium btn-sm" %>
```

- [ ] **Step 9: Run the controller test**

Run: `bin/rails test test/controllers/tasks_export_test.rb -v`
Expected: 4 runs, 0 failures.

- [ ] **Step 10: Run the whole suite**

Run: `bin/rails test`
Expected: all green, no new failures versus the Task 1 baseline.

- [ ] **Step 11: Commit**

```bash
git add app/services app/controllers app/views/tasks config/routes.rb test
git commit -m "feat: export weekly timing and monthly stats as CSV and Excel"
```

**PHASE 3 COMPLETE — the full spec is implemented.**

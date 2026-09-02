# Task Manager: Client Sprints, Subtasks, Team Hours, CSV

Date: 2026-09-03
Status: Approved design, not yet implemented

## Problem

The Task Manager module tracks one flat list of tasks a manager assigns to their
own direct reports. Three gaps block the way the team actually works:

1. **No department-wide picture.** `TasksController#dashboard` scopes to
   `Task.for_manager(current_user)` — tasks *you* assigned. A manager cannot see
   what every executive in the department logged today, this week, or this month.
2. **No structure for client work.** Work arrives as "gnexteriors wants a CRM" —
   a multi-week build for a named client, broken into weekly cycles. The app has
   no client, project or sprint concept, and no subtasks.
3. **No bulk load or reporting export.** Every task is typed in by hand, and
   hours cannot be exported for review or billing.

## Goals

- A manager sees daily and weekly hours for **every executive in their department**,
  covering both task time and attendance time.
- Work organises as **Client → Project → Sprint → Task → Subtask**.
- A manager **bulk-imports** a sprint's tasks and subtasks from CSV, Jira/ClickUp style.
- A manager **exports** weekly timing and monthly stats.

## Non-Goals

- Executives do not import CSV; managers still assign all work.
- The executive's My Tasks page keeps its current shape — only subtask nesting is added.
- No cross-department or company-wide view. Department is the boundary.
- No manual Jira-style worklogs. The existing timer remains the only source of task time.
- No separate pages. Everything lands on the existing Task Manager dashboard.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Whose hours can a manager see? | Everyone in their department | Matches how the team is organised; broader than direct reports, narrower than company-wide |
| Which hours? | Task hours and attendance hours side by side, plus the gap | The gap between "clocked in" and "logged on tasks" is the number that matters |
| Daily attribution of task time | New `task_work_sessions` table | `total_duration` is written once at completion with no date breakdown, so multi-day tasks would dump all hours on one day |
| Subtasks | Full tasks with a `parent_id` | Own assignee, timer, status and SLA; lets CSV import use the same columns |
| Sprints | Under Client → Project | A CRM build spans many weeks; weekly sprints hang off a project, projects off a client |
| CSV | Manager imports sprint tasks/subtasks; exports are weekly timing and monthly stats | Preserves "a manager assigns work" |
| Placement | Tabs inside the existing dashboard | No new pages |

## Data Model

### New tables

**`clients`**
- `name` (string, not null)
- `department_id` (bigint, not null, FK)
- `active` (boolean, default true, not null)
- `notes` (text)
- Unique index on `(department_id, name)`

**`projects`**
- `client_id` (bigint, not null, FK)
- `name` (string, not null)
- `description` (text)
- `status` (string, not null, default `"planned"`) — `planned` / `active` / `on_hold` / `completed`
- `start_date` (date), `target_end_date` (date)
- Unique index on `(client_id, name)`

**`sprints`**
- `project_id` (bigint, not null, FK)
- `name` (string, not null)
- `goal` (text)
- `start_date` (date, not null), `end_date` (date, not null)
- `status` (string, not null, default `"planned"`) — `planned` / `active` / `completed`
- Unique index on `(project_id, name)`; index on `(project_id, start_date)`

**`task_work_sessions`**
- `task_id` (bigint, not null, FK)
- `user_id` (bigint, not null, FK) — denormalised from the task's assignee so the
  hours query never joins `tasks`
- `started_at` (datetime, not null), `ended_at` (datetime)
- `duration_seconds` (integer, not null, default 0)
- Index on `(user_id, started_at)`, index on `task_id`

### Changes to `tasks`

- `parent_id` (bigint, nullable, FK to `tasks`) — index
- `sprint_id` (bigint, nullable, FK) — index
- `position` (integer, default 0, not null)

`total_duration` stays as a cached rollup so existing readers keep working.

### Associations

```
Department has_many :clients
Client      has_many :projects
Project     has_many :sprints
Sprint      has_many :tasks
Task        belongs_to :parent, optional, class_name: "Task"
Task        has_many   :subtasks, class_name: "Task", foreign_key: :parent_id
Task        has_many   :work_sessions, class_name: "TaskWorkSession"
```

### Rules

- **Subtask depth is one level.** A task with a `parent_id` may not itself be a
  parent. Validated on `Task`.
- **A subtask inherits its parent's sprint.** Set on save; a subtask's `sprint_id`
  is never assigned directly.
- **Assignment widens to the department.** `Task#assigned_to_is_a_direct_report_executive`
  currently requires `assigned_by.direct_reports.include?(assigned_to)`. It becomes
  `assigned_to.department_id == assigned_by.department_id` plus the existing
  "must hold the Executive role" check, and is renamed
  `assigned_to_is_a_department_executive`. Without this, sprint work cannot be
  assigned to executives reporting to another manager.
- `task_type_belongs_to_managers_department` is unchanged.
- A sprint's project's client must belong to the manager's department.

## Work Sessions

Work sessions replace the single duration field as the source of truth for *when*
time was spent. `Task#total_duration` remains a cached rollup.

| Transition | Session effect |
|---|---|
| `start!` | Open a session: `started_at = now`, `ended_at = nil` |
| `pause!` | Close the open session: `ended_at = now`, compute `duration_seconds` |
| `resume!` | Open a new session |
| `complete!` | Close the open session; recompute `total_duration` from the sum |

**Midnight splitting.** A session is split at the day boundary when it is closed:
a session from 22:00 Monday to 02:00 Tuesday is stored as two rows (22:00–00:00,
00:00–02:00). A daily `SUM` is then always correct with no date arithmetic in the
query. Sessions left open across midnight are split when closed, not by a job.

**Backfill.** A data migration creates one session per completed task:
`started_at = ended_at - total_duration`, `ended_at = ended_at`, split at midnight
by the same code path. Tasks with a null `ended_at` or `total_duration` are skipped.

**Parent rollup.** A parent task's reported hours are its own sessions plus every
subtask's sessions. Computed in the query object, not stored.

## Reporting

`Reports::ExecutiveHours.new(department:, range:)` returns a matrix:

```ruby
{ user_id => { date => { task_seconds:, attendance_seconds:, gap_seconds: } } }
```

The executive set is every employed user in the department holding the Executive
role. Built from exactly two grouped aggregates, regardless of how many executives or
days are in range:

1. `TaskWorkSession.where(user_id: ids, started_at: range).group(:user_id, "DATE(started_at)").sum(:duration_seconds)`
2. `TimeClock.where(user_id: ids, clock_in: range).group(:user_id, "DATE(clock_in)").sum("COALESCE(total_duration,0) - COALESCE(break_duration,0)")`

`gap_seconds` is `attendance_seconds - task_seconds`, floored at zero.

Sessions belong to whoever worked them, so a subtask assigned to a different
executive counts toward that executive's hours, never the parent's assignee.

This is the known N+1 hazard in this codebase — the TimeClock breaks lookups that
ignore eager loads. The query object must never iterate records to sum, and a test
asserts a fixed query count as the executive list grows.

The same object serves the daily grid, weekly totals, monthly stats and both exports.

## UI

Everything lives in `app/views/tasks/dashboard.html.erb` behind Bootstrap
`nav-tabs`, styled to match the existing page. No new pages.

**Tasks tab** — the current table, scoped to the department instead of
`for_manager`. Subtasks nest under their parent. Sprint and "assigned by me"
filters join the existing status and executive filters, so the old
tasks-I-assigned view is still one click away. Existing stat cards recompute on the
wider scope.

**Team Hours tab** — a grid of department executives by the seven days of the
selected week. Each cell shows task hours over attendance hours; the row ends in
a weekly total and a gap column. A week picker steps back and forward; a Monthly
toggle swaps the day columns for weeks-of-month and shows the monthly stat set.

**Sprints tab** — client and project selectors, then that project's sprints with
progress (done/total) and hours burned. Selecting a sprint expands its tasks
inline. Creating and editing clients, projects and sprints uses modals, matching
the existing "Assign New Task" modal.

**My Tasks** (`app/views/tasks/my_tasks.html.erb`) — unchanged except that
subtasks nest under their parent, each with its own start/pause/resume/complete
controls. No sprint grouping, no hours summary.

**Access.** Every action keeps the existing `authorize_page!("task_manager")` and
`department.task_manager_enabled?` gates. Managers manage clients, projects and
sprints in-app; no ActiveAdmin round-trip.

## CSV Import

Manager only. Modal on the dashboard.

Columns:

```
Key, Title, Description, Parent, Assignee Email, Task Type, Priority, Due Date, SLA Minutes, Sprint
```

- `Key` is a free-text row identifier meaningful only within the file.
- A subtask row sets `Parent` to its parent row's `Key`. Parent rows may appear
  after their children; resolution is a second pass over the parsed file.
- `Assignee Email` must match an Executive in the importing manager's department.
- `Task Type` resolves by name within the manager's department. An unknown type is
  an error unless "create missing task types" is ticked, mirroring the `__new__`
  branch in `TasksController#create`.
- `Sprint` resolves by name within the selected project.
- `Priority` must be one of `Task::PRIORITIES`. Blank defaults to `normal`.
- `Due Date` accepts `YYYY-MM-DD` and `DD/MM/YYYY`.

**Flow:** upload → dry-run preview listing every row as valid or with its specific
error → confirm → commit.

**Commit is one transaction.** A file containing any invalid row imports nothing.
Cap: 1000 rows.

New routes, none of which render a page of their own: `POST /tasks/import_preview`
renders the validated row list back into the modal, `POST /tasks/import` commits.

## CSV / Excel Export

CSV and Excel, using `caxlsx`, already in the Gemfile.

1. **Weekly timing** — one row per executive per day: task hours, attendance
   hours, gap; weekly totals per executive.
2. **Monthly stats** — one row per executive: task hours, attendance hours, tasks
   completed, over-SLA count, average task duration.
3. **Task list** — the currently filtered dashboard table, subtasks included.

Exports respect the active filters and the department boundary.

Routes: `GET /tasks/export` with a `report` parameter (`weekly_timing`,
`monthly_stats`, `task_list`) and a `format` of `csv` or `xlsx`. These return a
file download, not a page.

## Testing

Minitest with fixtures, following `test/models/time_clock_test.rb`.

**Models**
- A session opens on start, closes on pause, reopens on resume, closes on complete.
- A session spanning midnight is stored as two rows summing to the same duration.
- A parent task's reported hours include its subtasks'.
- A subtask cannot itself have a subtask.
- A task may be assigned to any Executive in the manager's department, and not to
  an executive in another department.
- A subtask's sprint always matches its parent's.

**Query**
- `Reports::ExecutiveHours` returns correct per-day task, attendance and gap seconds.
- Its query count stays fixed as the number of executives grows.

**Import**
- A valid file creates tasks and subtasks with the right parent links.
- A file with one invalid row creates nothing.
- Parent rows resolve regardless of row order.
- A subtask of a subtask is rejected.
- An assignee outside the manager's department is rejected.

**Controllers**
- A manager in department A sees no department B tasks, hours, clients or sprints.
- A department with `task_manager_enabled? == false` is redirected as today.

## Migration Order

1. Create `clients`, `projects`, `sprints`.
2. Add `parent_id`, `sprint_id`, `position` to `tasks`.
3. Create `task_work_sessions`.
4. Backfill sessions from completed tasks.
5. Relax the assignment validation to department scope.

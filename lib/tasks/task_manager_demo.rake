# Demo data for the Task Manager: a client, a project, two weekly sprints, and
# tasks with subtasks and logged hours spread across the current week.
#
#   bin/rails task_manager:seed_demo    # create it
#   bin/rails task_manager:clear_demo   # remove exactly what seed_demo created
#
# Everything it creates is tagged by client name, so clear_demo never touches
# real data.
namespace :task_manager do
  DEMO_CLIENT = "GN Exteriors".freeze

  desc "Seed demo client, project, sprints and tasks for the WEB department"
  task seed_demo: :environment do
    department = Department.find_by(name: "WEB")
    abort "No WEB department found." if department.nil?

    manager = User.employed.joins(:access_role)
                  .find_by(department_id: department.id, roles: { name: "Manager" })
    executives = User.employed.joins(:access_role)
                     .where(department_id: department.id, roles: { name: "Executive" })
                     .order(:name).to_a
    abort "Need a manager and at least two executives in WEB." if manager.nil? || executives.size < 2

    client = Client.find_or_create_by!(name: DEMO_CLIENT, department: department) do |c|
      c.notes = "Demo client created by task_manager:seed_demo"
    end
    project = Project.find_or_create_by!(client: client, name: "CRM") do |p|
      p.description = "Custom CRM build"
      p.status = "active"
      p.start_date = Date.current.beginning_of_week - 7
    end

    last_week = Sprint.find_or_create_by!(project: project, name: "Week 1") do |s|
      s.goal = "Auth, roles and contact records"
      s.start_date = Date.current.beginning_of_week - 7
      s.end_date = Date.current.beginning_of_week - 1
      s.status = "completed"
    end
    this_week = Sprint.find_or_create_by!(project: project, name: "Week 2") do |s|
      s.goal = "Deals pipeline and reporting"
      s.start_date = Date.current.beginning_of_week
      s.end_date = Date.current.end_of_week
      s.status = "active"
    end

    build = TaskType.find_or_create_by!(name: "Bug Fix", department: department) { |t| t.sla_minutes = 45 }
    onboarding = TaskType.find_or_create_by!(name: "Client Onboarding", department: department) { |t| t.sla_minutes = 90 }

    a, b = executives[0], executives[1]
    monday = Date.current.beginning_of_week

    # [sprint, title, assignee, type, status, day offset, hours worked]
    plan = [
      [last_week, "Login and session handling", a, build,      :completed, -5, 3.5],
      [last_week, "Role and permission matrix", b, build,      :completed, -4, 5.0],
      [this_week, "Deals pipeline board",       a, onboarding, :completed,  0, 4.0],
      [this_week, "Pipeline drag and drop",     b, build,      :completed,  1, 2.5],
      [this_week, "Reporting dashboard",        a, onboarding, :in_progress, 2, 1.5],
      [this_week, "CSV export of deals",        b, build,      :pending,     3, 0]
    ]

    created = []
    plan.each do |sprint, title, user, type, status, offset, hours|
      next if Task.exists?(title: title, sprint_id: sprint.id)

      started = (monday + offset.days).to_time.change(hour: 10)
      task = Task.new(title: title, priority: (hours > 4 ? "urgent" : "normal"),
                      sprint: sprint, assigned_to: user, assigned_by: manager,
                      task_type: type, due_date: (monday + offset.days + 2))
      task.status = status.to_s
      task.started_at = started unless status == :pending
      if status == :completed
        task.ended_at = started + hours.hours
        task.total_duration = (hours * 3600).to_i
        task.over_sla = task.total_duration > task.sla_seconds && task.sla_seconds.positive?
      end
      task.save!

      if hours.positive?
        TaskWorkSession.create!(task_id: task.id, user_id: user.id, started_at: started,
                                ended_at: started + hours.hours, duration_seconds: (hours * 3600).to_i)
      end
      created << task
    end

    # A parent with two subtasks, to show nesting and the rollup.
    parent = Task.find_by(title: "Deals pipeline board", sprint_id: this_week.id)
    if parent && parent.subtasks.empty?
      [["Card layout and styling", a, 1.0], ["Stage transition rules", b, 1.5]].each_with_index do |(title, user, hours), i|
        started = (monday + 1.day).to_time.change(hour: 14 + i)
        sub = Task.new(title: title, priority: "normal", parent: parent,
                       assigned_to: user, assigned_by: manager, task_type: build)
        sub.status = "completed"
        sub.started_at = started
        sub.ended_at = started + hours.hours
        sub.total_duration = (hours * 3600).to_i
        sub.save!
        TaskWorkSession.create!(task_id: sub.id, user_id: user.id, started_at: started,
                                ended_at: started + hours.hours, duration_seconds: (hours * 3600).to_i)
        created << sub
      end
    end

    puts "Seeded #{client.name} / #{project.name}"
    puts "  sprints: #{project.sprints.count} (#{project.sprints.pluck(:name).join(', ')})"
    puts "  tasks:   #{created.size} new (#{Task.where(sprint_id: project.sprints.select(:id)).count} total in these sprints)"
    puts "  hours:   #{(TaskWorkSession.where(task_id: Task.where(sprint_id: project.sprints.select(:id)).select(:id)).sum(:duration_seconds) / 3600.0).round(1)}h logged"
    puts "Open /tasks/dashboard — Tasks, Team Hours and Sprints tabs are all populated."
  end

  desc "Remove everything task_manager:seed_demo created"
  task clear_demo: :environment do
    client = Client.find_by(name: DEMO_CLIENT)
    if client.nil?
      puts "Nothing to remove."
      next
    end

    sprint_ids = Sprint.joins(:project).where(projects: { client_id: client.id }).pluck(:id)
    tasks = Task.where(sprint_id: sprint_ids)
    # Subtasks first: destroying a parent cascades, but count them for the report.
    count = tasks.count
    tasks.destroy_all
    Sprint.where(id: sprint_ids).destroy_all
    client.projects.destroy_all
    client.destroy!

    puts "Removed #{DEMO_CLIENT}: #{count} task(s), #{sprint_ids.size} sprint(s), and the client."
  end
end

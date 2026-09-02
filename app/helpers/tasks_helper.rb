module TasksHelper
  def hours_label(seconds)
    seconds = seconds.to_i
    return "—" if seconds.zero?

    h, rem = seconds.divmod(3600)
    m, = rem.divmod(60)
    h.positive? ? "#{h}h #{m}m" : "#{m}m"
  end

  # "Client — Project" optgroups holding that project's sprints, so a manager
  # picks the client and the cycle in one control.
  def sprint_options_grouped_by_project(sprints = @sprints)
    sprints.group_by(&:project).map do |project, project_sprints|
      ["#{project.client.name} — #{project.name}",
       project_sprints.map { |s| [s.name, s.id] }]
    end
  end
end

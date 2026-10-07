# Builds the employee app's top navigation, so the navbar partial only has to
# render a list. Who sees which entry is decided here, in one place.
module NavbarHelper
  # badge_tone: :count for "how many of mine", :alert for "waiting on me".
  NavItem = Struct.new(:label, :path, :icon, :badge, :badge_tone, :external, :children, keyword_init: true) do
    def dropdown?
      children.present?
    end
  end

  FEEDBACK_URL = "http://10.10.30.30:5173".freeze

  def primary_nav_items
    [
      NavItem.new(label: "Dashboard", path: root_path, icon: "gauge-high"),
      feedback_nav_item,
      NavItem.new(label: "My Requests", path: my_requests_edit_requests_path, icon: "clock-rotate-left",
                  badge: current_user.edit_requests.count, badge_tone: :count),
      NavItem.new(label: "My Leaves", path: my_leaves_leaves_path, icon: "calendar-day",
                  badge: current_user.leaves.count, badge_tone: :count),
      tasks_nav_item,
      # Review queues are gated by the role's page permissions, not a role name.
      (NavItem.new(label: "Edit Requests", path: edit_requests_path, icon: "user-pen",
                   badge: edit_requests_count, badge_tone: :alert) if can_view?("edit_requests.review")),
      (NavItem.new(label: "Leave Requests", path: leaves_path, icon: "calendar-check",
                   badge: leaves_count, badge_tone: :alert) if can_view?("leaves.review")),
      (NavItem.new(label: "Organogram", path: organogram_path, icon: "sitemap") if can_view?("organogram"))
    ].compact
  end

  # A top-level entry is active on its own page, or on any of its children's.
  def nav_item_active?(item)
    return item.children.any? { |child| current_page?(child.path) } if item.dropdown?

    !item.external && current_page?(item.path)
  end

  private

  # Needs both the admin toggle (Roles & Permissions) and someone to send it
  # to: managers who don't report to an HOD have no feedback target.
  def feedback_nav_item
    return unless can_view?("feedback") && current_user.can_give_feedback?

    NavItem.new(label: "Feedback", icon: "comment-dots", external: true,
                path: "#{FEEDBACK_URL}?#{{ department: current_user.feedback_department }.to_query}")
  end

  # The Tasks module is off entirely for departments without it enabled
  # (admin -> Settings -> Departments).
  def tasks_nav_item
    return unless current_user.org_department&.task_manager_enabled?

    open_tasks = current_user.tasks.where(status: %w[pending in_progress paused]).count
    children = [NavItem.new(label: "My Tasks", path: my_tasks_tasks_path, icon: "list-check",
                            badge: open_tasks, badge_tone: :count)]
    children << NavItem.new(label: "Task Manager", path: dashboard_tasks_path, icon: "tasks") if can_view?("task_manager")

    NavItem.new(label: "Tasks", path: "#", icon: "list-check", badge: open_tasks, badge_tone: :count, children: children)
  end
end

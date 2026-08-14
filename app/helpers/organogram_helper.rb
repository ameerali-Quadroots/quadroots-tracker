module OrganogramHelper
  # Builds the whole reporting tree from a single query.
  #
  # Someone with more than one manager appears once under each of them - the
  # chart shows every reporting line rather than picking a "primary" one.
  #
  # Returns [roots, children_by_parent_id] where roots are the users with no
  # manager in scope, sorted most senior first. Anyone not yet given a
  # "Reports to" shows up as a root, so the chart is useful before the tree
  # is fully filled in.
  def organogram_tree(scope = User.employed)
    users = scope.includes(:access_role, :org_department, :managers, image_attachment: :blob).to_a
    ids   = users.map(&:id).to_set

    children = Hash.new { |h, k| h[k] = [] }
    users.each do |u|
      manager_ids_in_scope = u.managers.map(&:id) & ids.to_a
      if manager_ids_in_scope.empty?
        children[nil] << u
      else
        manager_ids_in_scope.each { |manager_id| children[manager_id] << u }
      end
    end
    children.each_value { |group| group.sort_by! { |u| [u.access_role&.rank || 999, u.name.to_s] } }

    roots = children[nil]
    roots.sort_by! { |u| [u.access_role&.rank || 999, u.name.to_s] }

    [roots, children]
  end

  # Total people under this node, at any depth, using the prebuilt map.
  def organogram_descendant_count(user, children)
    (children[user.id] || []).sum { |child| 1 + organogram_descendant_count(child, children) }
  end

  # Colour a role badge consistently by seniority band.
  def organogram_role_color(user)
    case user.access_role&.rank
    when nil          then { bg: "#F1F5F9", fg: "#475569" }
    when 0..9         then { bg: "#FEF3C7", fg: "#92400E" }
    when 10..29       then { bg: "#EDE9FE", fg: "#5B21B6" }
    when 30..49       then { bg: "#DBEAFE", fg: "#1E40AF" }
    else                   { bg: "#DCFCE7", fg: "#166534" }
    end
  end
end

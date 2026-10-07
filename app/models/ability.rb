# app/models/ability.rb
#
# Admin-panel authorization. Rules are built from the role's permission matrix
# (Roles -> edit -> Permissions in the admin panel), not from hardcoded role
# names, so a new role takes effect without a deploy.
#
# ActiveAdmin routes every screen through this via
# config.authorization_adapter = ActiveAdmin::CanCanAdapter, which also hides
# menu entries and the New/Edit/Delete buttons for anything not permitted.
class Ability
  include CanCan::Ability

  # ActiveAdmin page name => subject in Permission::RESOURCES.
  GATED_PAGES = { "KPI" => "Kpi", "Analytics" => "Analytics" }.freeze

  def initialize(user)
    return if user.blank?

    role = user.try(:access_role)

    # Account not linked to a role yet: fall back to the previous default so
    # nobody is locked out mid-rollout.
    if role.nil?
      can :read, :all
      can :export, ActiveAdmin::Page, name: "KPI"
      return
    end

    if role.super_admin?
      can :manage, :all
      return
    end

    grant_resources(role)

    # ActiveAdmin authorizes its custom pages (Dashboard, Organogram) with
    # :read against the page config object rather than a model. Every admin
    # could reach those under the old `can :read, :all`, so keep that.
    #
    # Custom page_actions (dashboard.rb's live_state/monthly_overview) are
    # authorized by CanCan using their own action name rather than :read, so
    # they need to be granted explicitly too. Both self-restrict further
    # inside their block (monthly_overview renders "Forbidden" for non
    # super/qa admins), so it's safe to open the CanCan gate for everyone.
    can :read, ActiveAdmin::Page
    can :live_state, ActiveAdmin::Page
    can :monthly_overview, ActiveAdmin::Page

    # These pages are the exception: each is gated by its own "Read ..." box
    # in the matrix, which also covers the KPI page's Excel export page_action.
    GATED_PAGES.each do |page_name, subject|
      if role.can?(:read, subject)
        can :export, ActiveAdmin::Page, name: page_name
      else
        cannot :read, ActiveAdmin::Page, name: page_name
      end
    end
  end

  private

  def grant_resources(role)
    role.permissions.resources.group_by(&:subject).each do |subject_name, permissions|
      subject = subject_name.safe_constantize
      next if subject.nil?

      actions = permissions.map { |p| p.action.to_sym }

      # EditRequest/Leave's admin-panel Approve/Reject buttons are custom
      # member_actions (app/admin/edit_requests.rb, app/admin/leaves.rb).
      # ActiveAdmin's CanCanAdapter authorizes those against the literal
      # :approve/:reject action name - only the standard CRUD verbs get
      # remapped to :update - so without this, granting "Edit" alone leaves
      # the buttons silently unauthorized even though update access is
      # clearly the intent.
      actions += %i[approve reject] if actions.include?(:update)

      # All four actions ticked means full control, so `authorize! :manage, X`
      # (used by app/admin/admin_users.rb) behaves the way the matrix reads.
      actions = [:manage] if (Permission::ACTIONS.map(&:to_sym) - actions).empty?

      can actions, subject
    end
  end
end

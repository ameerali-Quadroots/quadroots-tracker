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

  def initialize(user)
    return if user.blank?

    role = user.try(:access_role)

    # Account not linked to a role yet: fall back to the previous default so
    # nobody is locked out mid-rollout.
    if role.nil?
      can :read, :all
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
    can :read, ActiveAdmin::Page
  end

  private

  def grant_resources(role)
    role.permissions.resources.group_by(&:subject).each do |subject_name, permissions|
      subject = subject_name.safe_constantize
      next if subject.nil?

      actions = permissions.map { |p| p.action.to_sym }

      # All four actions ticked means full control, so `authorize! :manage, X`
      # (used by app/admin/admin_users.rb) behaves the way the matrix reads.
      actions = [:manage] if (Permission::ACTIONS.map(&:to_sym) - actions).empty?

      can actions, subject
    end
  end
end

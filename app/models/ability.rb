# app/models/ability.rb
class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user.present?  # Handle guest users if needed

    case user.role
    when "super_admin"
      can :manage, :all  
    when "manage_admin"
      can [:read, :update, :destroy], User
      can :create, User
      can :read, :all
      cannot :manage, AdminUser
      cannot :manage, EditRequest
      cannot :manage, Leave

    when "admin"
      can :read, :all
      cannot :manage, User
      cannot :manage, AdminUser
      cannot :manage, EditRequest
      cannot :manage, Leave

    when "qa_admin"
      can :read, :all
      cannot :manage, User
      cannot :manage, AdminUser
      cannot :manage, EditRequest
      cannot :manage, Leave
    else
      can :read, :all
    end
  end
end

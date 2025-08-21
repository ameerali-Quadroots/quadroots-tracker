class Ability
  include CanCan::Ability

  def initialize(user)
    if user.admin?
      can :manage, :all # Admin can manage everything
    else
      can :read, :all # Employees can read their own data
      can :clock_in, TimeClock # Ability to clock in for employees
    end
  end
end

# Derives an initial reporting tree from the structure the app already assumed
# implicitly, so the organogram is populated and Phase 5 can replace the
# hardcoded checks without changing who sees whom.
#
# The rules below are lifted straight from the existing code:
#   - User::HOD_MANAGED_DEPARTMENTS (WEB/SEO/ADS/CONTENT) report to the HOD
#   - the HOD is the Manager sitting in the "HOD'S" department
#     (app/services/notification_service.rb looked them up exactly that way)
#   - executives are scoped to their own department's manager
#     (app/controllers/leaves_controller.rb, edit_requests_controller.rb)
#
# Everything it does is reversible: reporting edges live in `user_managers`
# and every assumption is printed. Run with DRY_RUN=true first.
class HierarchyBootstrapper
  HOD_DEPARTMENT = "HOD'S".freeze
  HOD_MANAGED = %w[WEB SEO ADS CONTENT].freeze

  def self.call(dry_run: false, io: $stdout)
    new(dry_run: dry_run, io: io).call
  end

  def initialize(dry_run: false, io: $stdout)
    @dry_run = dry_run
    @io = io
    @notes = []
  end

  def call
    ActiveRecord::Base.transaction do
      ceo = find_or_promote_ceo
      hod = find_or_promote_hod(ceo)

      assign_directors(ceo)
      assign_managers(ceo, hod)
      assign_staff(ceo)

      report(ceo)

      if @dry_run
        say ""
        say "DRY RUN - rolling back, nothing was written."
        raise ActiveRecord::Rollback
      end
    end
  end

  private

  def say(msg) = @io.puts(msg)
  def note(msg) = @notes << msg

  def employed = User.employed

  def role(name) = Role.find_by(name: name)

  # The CEO is whoever already holds the CEO role; failing that, the
  # Executive Board member with no role at all (there is exactly one).
  def find_or_promote_ceo
    ceo = employed.find_by(role_id: role("CEO")&.id)
    return ceo if ceo

    candidates = employed.where(department: "Executive Board", role_id: nil).to_a
    if candidates.size != 1
      raise "Cannot identify the CEO: #{candidates.size} Executive Board members have no role. " \
            "Assign the CEO role by hand in the admin panel, then re-run."
    end

    ceo = candidates.first
    ceo.update!(access_role: role("CEO"))
    ceo.managers = []
    note "Promoted #{ceo.name} (#{ceo.email}) to the CEO role - they were the only Executive Board member without one."
    ceo
  end

  # The HOD is the Manager sitting in the "HOD'S" department.
  def find_or_promote_hod(ceo)
    hod = employed.find_by(role_id: role("HOD")&.id)
    return hod if hod

    candidates = employed.where(department: HOD_DEPARTMENT).to_a
    if candidates.empty?
      note "No one is in the #{HOD_DEPARTMENT} department, so managers of #{HOD_MANAGED.join('/')} report to the CEO."
      return nil
    end
    if candidates.size > 1
      note "#{candidates.size} people are in #{HOD_DEPARTMENT}; used #{candidates.first.name}. Correct this in the admin panel if wrong."
    end

    hod = candidates.first
    hod.update!(access_role: role("HOD"))
    hod.managers = [ceo]
    note "Promoted #{hod.name} to the HOD role (they were the Manager in #{HOD_DEPARTMENT})."
    hod
  end

  def assign_directors(ceo)
    employed.where(role_id: role("Director")&.id).where.not(id: ceo.id).find_each do |d|
      d.managers = [ceo]
    end
  end

  def assign_managers(ceo, hod)
    manager_role = role("Manager")
    return if manager_role.nil?

    employed.where(role_id: manager_role.id).find_each do |m|
      next if m.id == ceo.id || (hod && m.id == hod.id)

      if HOD_MANAGED.include?(m[:department]) && hod
        m.managers = [hod]
      else
        m.managers = [ceo]
        note "#{m.name} (Manager, #{m[:department]}) reports to the CEO - #{m[:department]} is not one of the HOD's departments." unless HOD_MANAGED.include?(m[:department])
      end
    end
  end

  # Everyone else reports to their own department's manager.
  def assign_staff(ceo)
    senior_ids = employed.where(role_id: [role("Manager")&.id, role("Director")&.id, role("HOD")&.id, role("CEO")&.id].compact).pluck(:id)

    managers_by_dept = employed.where(role_id: role("Manager")&.id).order(:id).group_by { |m| m[:department] }
    managers_by_dept.each do |dept, list|
      next if list.size < 2

      note "#{dept} has #{list.size} managers (#{list.map(&:name).join(', ')}); its staff were put under #{list.first.name}."
    end

    employed.where.not(id: senior_ids).find_each do |u|
      manager = managers_by_dept[u[:department]]&.first
      if manager.nil?
        u.managers = [ceo]
        note "#{u[:department]} has no manager, so its staff report to the CEO." unless @notes.any? { |n| n.start_with?("#{u[:department]} has no manager") }
      else
        u.managers = [manager]
      end
    end
  end

  def report(ceo)
    roots = employed.where(reports_to_id: nil)
    say "CEO: #{ceo.name} (#{ceo.email})"
    say "Assigned a manager to #{employed.where.not(reports_to_id: nil).count} of #{employed.count} employees."
    say "Top of tree (#{roots.count}): #{roots.map(&:name).join(', ')}"

    say ""
    say "Depth check:"
    employed.includes(:access_role).order(:name).group_by { |u| u.access_role&.name }.each do |role_name, users|
      say "  #{(role_name || 'no role').ljust(12)} #{users.size}"
    end

    return if @notes.empty?

    say ""
    say "ASSUMPTIONS MADE - review these in the admin panel:"
    @notes.each { |n| say "  - #{n}" }
  end
end

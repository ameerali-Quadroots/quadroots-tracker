# Seeds the permission catalogue, the roles and departments that already exist
# as hardcoded strings, and backfills users onto them.
#
# Idempotent - safe to re-run after adding a permission to Permission::RESOURCES
# or Permission::PAGES. The permission grants below reproduce the old
# app/models/ability.rb case statement exactly, so switching Ability over to the
# matrix does not change what any existing admin can do.
class RoleSeeder
  # Resources the old Ability explicitly withheld with `cannot :manage`.
  DENIED_FOR_ADMINS = %w[AdminUser EditRequest Leave].freeze

  ADMIN_ROLES = {
    "super_admin" => {
      name: "Super Admin", rank: 0, system: true,
      description: "Full access to everything. Cannot be deleted or restricted."
    },
    "manage_admin" => {
      name: "Manage Admin", rank: 10,
      description: "Reads everything except admin users, edit requests and leaves; manages employees."
    },
    "admin" => {
      name: "Admin", rank: 20,
      description: "Read-only access, excluding employees, admin users, edit requests and leaves."
    },
    "qa_admin" => {
      name: "QA Admin", rank: 20,
      description: "Read-only access for QA, excluding employees, admin users, edit requests and leaves."
    }
  }.freeze

  MANAGER_PAGES = %w[
    feedback hosting organogram
    team_status manager_status executive_timesheets department_stats
    edit_requests.review leaves.review
  ].freeze

  STAFF_PAGES = %w[feedback hosting organogram].freeze

  EMPLOYEE_ROLES = {
    "CEO"       => { rank: 5,  pages: MANAGER_PAGES, description: "Company head. Sees the whole organisation." },
    "Director"  => { rank: 20, pages: MANAGER_PAGES, description: "Board / director level." },
    "HOD"       => { rank: 30, pages: MANAGER_PAGES, description: "Head of department. Oversees managers." },
    "Manager"   => { rank: 40, pages: MANAGER_PAGES, description: "Manages a department's executives." },
    "Executive" => { rank: 60, pages: STAFF_PAGES,   description: "Individual contributor." },
    "Intern"    => { rank: 70, pages: STAFF_PAGES,   description: "Intern." }
  }.freeze

  def self.call(dry_run: false, io: $stdout)
    new(dry_run: dry_run, io: io).call
  end

  def initialize(dry_run: false, io: $stdout)
    @dry_run = dry_run
    @io = io
    @unmatched = Hash.new { |h, k| h[k] = [] }
  end

  def call
    ActiveRecord::Base.transaction do
      sync_permissions
      sync_departments
      sync_roles
      backfill
      report

      if @dry_run
        say ""
        say "DRY RUN - rolling back, nothing was written."
        raise ActiveRecord::Rollback
      end
    end

    @unmatched
  end

  private

  def say(msg) = @io.puts(msg)

  def sync_permissions
    say "Permissions in catalogue: #{Permission.sync_catalogue!}"
  end

  def sync_departments
    names = (User.distinct.pluck(:department) + AdminUser.distinct.pluck(:department))
              .map { |n| n.to_s.strip }.reject(&:blank?).uniq.sort

    names.each_with_index do |name, i|
      dept = Department.find_or_initialize_by(name: name)
      dept.position = i
      dept.save!
    end

    say "Departments: #{Department.count} (#{names.join(', ')})"
  end

  def sync_roles
    ADMIN_ROLES.each do |slug, attrs|
      role = Role.find_or_initialize_by(slug: slug)
      role.assign_attributes(
        name: attrs[:name], scope: "admin", rank: attrs[:rank],
        description: attrs[:description], system: attrs[:system] || false, active: true
      )
      role.save!
      grant(role, admin_permission_keys(slug))
    end

    EMPLOYEE_ROLES.each do |name, attrs|
      role = Role.find_or_initialize_by(name: name)
      role.assign_attributes(
        scope: "employee", rank: attrs[:rank],
        description: attrs[:description], active: true
      )
      role.save!
      grant(role, attrs[:pages])
    end

    say ""
    Role.ordered.each do |r|
      say "  #{r.name.ljust(14)} scope=#{r.scope.ljust(9)} rank=#{r.rank.to_s.rjust(3)}  permissions=#{r.permissions.count}"
    end
  end

  # Grants exactly `keys`, revoking anything else the role had.
  def grant(role, keys)
    wanted  = Permission.where(key: keys)
    missing = keys - wanted.pluck(:key)
    say "  WARNING: unknown permission keys for #{role.name}: #{missing.join(', ')}" if missing.any?

    ids = wanted.pluck(:id)
    role.role_permissions.where.not(permission_id: ids).destroy_all
    (ids - role.role_permissions.pluck(:permission_id)).each do |pid|
      role.role_permissions.create!(permission_id: pid)
    end
    role.reload
  end

  # Mirrors the old `case admin_user.role` in app/models/ability.rb:
  #   super_admin  -> can :manage, :all
  #   manage_admin -> can :read, :all + full CRUD on User, minus AdminUser/EditRequest/Leave
  #   admin/qa     -> can :read, :all, minus User/AdminUser/EditRequest/Leave
  def admin_permission_keys(slug)
    all = Permission::RESOURCES.keys
    readable = (all - DENIED_FOR_ADMINS - ["User"]).map { |s| Permission.resource_key(s, "read") }

    case slug
    when "super_admin"
      all.flat_map { |s| Permission::ACTIONS.map { |a| Permission.resource_key(s, a) } }
    when "manage_admin"
      readable + Permission::ACTIONS.map { |a| Permission.resource_key("User", a) }
    when "admin", "qa_admin"
      readable
    else
      []
    end
  end

  def backfill
    role_by_name = Role.all.index_by { |r| r.name.downcase }
    role_by_slug = Role.all.index_by { |r| r.slug.downcase }
    dept_by_name = Department.all.index_by { |d| d.name.downcase }

    User.find_each do |u|
      role = role_by_name[u[:role].to_s.downcase]
      dept = dept_by_name[u[:department].to_s.downcase]
      @unmatched["user role"] << "##{u.id} #{u.email} (#{u[:role].inspect})" if role.nil?
      @unmatched["user department"] << "##{u.id} #{u.email} (#{u[:department].inspect})" if dept.nil?
      # update_columns: skip validations and the sync callback, which would
      # just write the same strings back.
      u.update_columns(role_id: role&.id, department_id: dept&.id)
    end

    AdminUser.find_each do |a|
      key  = a[:role].to_s.downcase
      role = role_by_slug[key] || role_by_name[key]
      dept = dept_by_name[a[:department].to_s.downcase]
      @unmatched["admin role"] << "##{a.id} #{a.email} (#{a[:role].inspect})" if role.nil?
      @unmatched["admin department"] << "##{a.id} #{a.email} (#{a[:department].inspect})" if dept.nil?
      a.update_columns(role_id: role&.id, department_id: dept&.id)
    end
  end

  def report
    say ""
    say "Employees:   #{User.where.not(role_id: nil).count}/#{User.count} role, " \
        "#{User.where.not(department_id: nil).count}/#{User.count} department"
    say "Admin users: #{AdminUser.where.not(role_id: nil).count}/#{AdminUser.count} role, " \
        "#{AdminUser.where.not(department_id: nil).count}/#{AdminUser.count} department"

    return if @unmatched.empty?

    say ""
    say "UNMATCHED - left null on purpose, assign these by hand in the admin panel:"
    @unmatched.each { |kind, rows| say "  #{kind}: #{rows.join(', ')}" }
  end
end

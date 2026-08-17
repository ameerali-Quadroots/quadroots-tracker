class Permission < ApplicationRecord
  KINDS   = %w[resource page].freeze
  ACTIONS = %w[read create update destroy].freeze

  # Every resource the admin panel can authorize, in display order.
  # subject => label shown in the permission matrix.
  RESOURCES = {
    "User"         => "Employees",
    "AdminUser"    => "Admin Users",
    "TimeClock"    => "Time Clocks",
    "Break"        => "Breaks",
    "EditRequest"  => "Edit Requests",
    "Leave"        => "Leaves",
    "Role"         => "Roles",
    "Department"   => "Departments",
    "ApprovalFlow" => "Approval Flows",
    "AppSetting"   => "Request Limits",
    "TaskType"     => "Task Types"
  }.freeze

  # Named screens in the employee-facing app. These replace the hardcoded
  # `role == "Manager"` / `department == "HOD'S"` checks.
  # key => [label, group]
  # NOTE: there is deliberately no "dashboard" permission. The dashboard is the
  # root path and authorize_page! redirects to root on refusal, so gating it
  # would loop forever. Every signed-in user reaches it.
  PAGES = {
    "feedback"             => ["Feedback link", "General"],
    "hosting"              => ["Hosting details", "General"],
    "organogram"           => ["Organogram", "General"],
    "team_status"          => ["Team status", "Team"],
    "manager_status"       => ["Live team status widget", "Team"],
    "executive_timesheets" => ["Team member timesheets", "Team"],
    "department_stats"     => ["Monthly department stats", "Team"],
    "task_manager"         => ["Task Manager (assign & track tasks)", "Team"],
    "edit_requests.review" => ["Review edit requests", "Approvals"],
    "leaves.review"        => ["Review leave requests", "Approvals"]
  }.freeze

  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :kind, inclusion: { in: KINDS }
  validates :key, presence: true, uniqueness: true
  validates :label, presence: true

  scope :resources, -> { where(kind: "resource") }
  scope :pages, -> { where(kind: "page") }
  scope :ordered, -> { order(:position, :key) }

  def self.resource_key(subject, action)
    "#{subject.to_s.underscore}.#{action}"
  end

  def to_s
    label
  end

  # Idempotently upserts the catalogue above. Safe to re-run: adding a resource
  # or page is a one-line edit here followed by `rails permissions:sync`.
  def self.sync_catalogue!
    position = 0

    RESOURCES.each do |subject, label|
      ACTIONS.each do |action|
        position += 1
        record = find_or_initialize_by(key: resource_key(subject, action))
        record.assign_attributes(
          kind: "resource",
          subject: subject,
          action: action,
          label: "#{action.capitalize} #{label}",
          group: label,
          position: position
        )
        record.save!
      end
    end

    PAGES.each do |key, (label, group)|
      position += 1
      record = find_or_initialize_by(key: key)
      record.assign_attributes(
        kind: "page",
        subject: nil,
        action: nil,
        label: label,
        group: group,
        position: position
      )
      record.save!
    end

    # Drop catalogue entries that no longer exist in code.
    stale = where.not(key: RESOURCES.keys.flat_map { |s| ACTIONS.map { |a| resource_key(s, a) } } + PAGES.keys)
    stale.destroy_all

    count
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id kind subject action key label group position created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[roles role_permissions]
  end
end

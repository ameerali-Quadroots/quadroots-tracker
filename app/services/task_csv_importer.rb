require "csv"

# Parses a Jira/ClickUp-shaped CSV into validated rows, then (in commit!) turns
# them into tasks and subtasks inside one transaction.
#
# Two passes: parse each line, then resolve Parent references against the Key
# column so a parent may appear anywhere in the file, before or after its
# children.
class TaskCsvImporter
  MAX_ROWS = 1000
  REQUIRED_HEADERS = ["Title", "Assignee Email", "Task Type"].freeze
  HEADERS = ["Key", "Title", "Description", "Parent", "Assignee Email",
             "Task Type", "Priority", "Due Date", "SLA Minutes"].freeze

  Row = Struct.new(:line, :key, :title, :description, :parent_key, :assignee_email,
                   :type_name, :priority, :due_date, :sla_minutes, :assignee,
                   :task_type, :errors, keyword_init: true)

  def initialize(csv_text:, manager:, sprint: nil, create_missing_types: false)
    @csv_text = csv_text.to_s
    @manager = manager
    @sprint = sprint
    @create_missing_types = create_missing_types
  end

  def rows
    @rows ||= parse
  end

  def valid? = rows.any? && rows.all? { |r| r.errors.empty? }

  def error_count = rows.count { |r| r.errors.any? }

  private

  def parse
    table = begin
      CSV.parse(@csv_text, headers: true)
    rescue CSV::MalformedCSVError => e
      return [fatal("The file could not be read as CSV: #{e.message}")]
    end

    missing = REQUIRED_HEADERS - (table.headers || []).compact.map(&:strip)
    return [fatal("The file is missing required column(s): #{missing.join(', ')}.")] if missing.any?
    return [fatal("The file has #{table.size} rows; the limit is #{MAX_ROWS} rows.")] if table.size > MAX_ROWS
    return [fatal("The file has no data rows.")] if table.size.zero?

    parsed = table.each_with_index.map { |csv_row, index| build_row(csv_row, index + 2) }
    validate_parents(parsed)
    parsed
  end

  def fatal(message)
    Row.new(line: 1, errors: [message])
  end

  def build_row(csv_row, line)
    row = Row.new(
      line: line,
      key: value(csv_row, "Key"),
      title: value(csv_row, "Title"),
      description: value(csv_row, "Description"),
      parent_key: value(csv_row, "Parent"),
      assignee_email: value(csv_row, "Assignee Email"),
      type_name: value(csv_row, "Task Type"),
      priority: value(csv_row, "Priority").presence&.downcase || "normal",
      sla_minutes: value(csv_row, "SLA Minutes").presence,
      errors: []
    )

    row.errors << "title is required" if row.title.blank?
    unless Task::PRIORITIES.include?(row.priority)
      row.errors << "priority must be one of #{Task::PRIORITIES.join(', ')}"
    end

    resolve_assignee(row)
    resolve_task_type(row)
    resolve_due_date(row, value(csv_row, "Due Date"))
    row
  end

  def value(csv_row, header)
    csv_row[header].to_s.strip
  end

  def resolve_assignee(row)
    return row.errors << "assignee email is required" if row.assignee_email.blank?

    row.assignee = department_executives[row.assignee_email.downcase]
    return if row.assignee

    row.errors << "#{row.assignee_email} is not an Executive in your department"
  end

  def department_executives
    @department_executives ||= User.employed.joins(:access_role)
                                   .where(department_id: @manager.department_id, roles: { name: "Executive" })
                                   .index_by { |u| u.email.to_s.downcase }
  end

  def resolve_task_type(row)
    return row.errors << "task type is required" if row.type_name.blank?

    row.task_type = task_types[row.type_name.downcase]
    return if row.task_type
    return if @create_missing_types

    row.errors << "task type '#{row.type_name}' does not exist in your department"
  end

  def task_types
    @task_types ||= TaskType.where(department_id: @manager.department_id)
                            .index_by { |t| t.name.to_s.downcase }
  end

  def resolve_due_date(row, raw)
    return if raw.blank?

    row.due_date = Date.strptime(raw, "%Y-%m-%d") rescue nil
    row.due_date ||= (Date.strptime(raw, "%d/%m/%Y") rescue nil)
    row.errors << "due date '#{raw}' is not YYYY-MM-DD or DD/MM/YYYY" if row.due_date.nil?
  end

  # Parents resolve after every line is parsed, so a child may precede its
  # parent in the file — which Jira exports routinely do.
  def validate_parents(parsed)
    by_key = parsed.reject { |r| r.key.blank? }.index_by(&:key)

    parsed.each do |row|
      next if row.parent_key.blank?

      parent = by_key[row.parent_key]
      if parent.nil?
        row.errors << "no row defines parent key '#{row.parent_key}'"
      elsif parent.parent_key.present?
        row.errors << "only one level of subtasks is allowed"
      end
    end
  end
end

# Creates one approval flow per existing edit-request type, reproducing today's
# behaviour (a Manager signs off, then an admin finalises from the admin panel),
# and backfills approval rows for requests created before the chain existed so
# nothing in flight gets stranded.
#
# Once seeded, an admin adds HOD / CEO steps from Settings -> Approval Flows.
class ApprovalFlowSeeder
  def self.call(dry_run: false, io: $stdout)
    new(dry_run: dry_run, io: io).call
  end

  def initialize(dry_run: false, io: $stdout)
    @dry_run = dry_run
    @io = io
  end

  def call
    ActiveRecord::Base.transaction do
      seed_flows
      seed_leave_flow
      list_flows
      backfill_existing
      backfill_existing_leaves

      if @dry_run
        say ""
        say "DRY RUN - rolling back, nothing was written."
        raise ActiveRecord::Rollback
      end
    end
  end

  private

  def say(msg) = @io.puts(msg)

  def manager_role
    @manager_role ||= Role.find_by(name: "Manager") or raise "No Manager role - run roles:seed_and_backfill first."
  end

  # The admin-panel sign-off that today's process ends with. Modelled as a real
  # step so a request the manager approved still sits waiting for an admin,
  # exactly as it does now. No User holds an admin-scope role, so only the
  # admin panel can settle it (EditRequest force_approve!/force_reject!).
  def admin_role
    @admin_role ||= Role.find_by(slug: "super_admin") or raise "No Super Admin role - run roles:seed_and_backfill first."
  end

  # One flow per request type in use, plus a catch-all for anything new.
  # The default chain reproduces today's behaviour: Manager, then admin panel.
  def seed_flows
    types = EditRequest.distinct.pluck(:request_type).compact.reject(&:blank?).sort
    (types + [nil]).each do |type|
      flow = ApprovalFlow.find_or_initialize_by(subject_type: "EditRequest", request_type: type)
      flow.name = type.presence || "Edit requests (catch-all)"
      flow.active = true
      flow.save!

      flow.approval_steps.destroy_all if ENV["RESET_STEPS"] == "true"
      next if flow.approval_steps.any?

      flow.approval_steps.create!(role: manager_role, position: 0, name: "Manager")
      flow.approval_steps.create!(role: admin_role, position: 1, name: "Admin panel")
    end
  end

  # Leave has no request_type column, so a single catch-all flow covers every
  # leave. Same default chain as edit requests: a Manager signs off, then an
  # admin finalises - so a leave can never reach "approved" without its
  # manager step clearing first, while reject remains available on whichever
  # step is currently pending (Approvable#reject!/#force_reject!).
  def seed_leave_flow
    flow = ApprovalFlow.find_or_initialize_by(subject_type: "Leave", request_type: nil)
    flow.name = "Leave requests"
    flow.active = true
    flow.save!

    flow.approval_steps.destroy_all if ENV["RESET_STEPS"] == "true"
    return if flow.approval_steps.any?

    flow.approval_steps.create!(role: manager_role, position: 0, name: "Manager")
    flow.approval_steps.create!(role: admin_role, position: 1, name: "Admin panel")
  end

  def list_flows
    say "Approval flows:"
    ApprovalFlow.order(:subject_type, :request_type).each do |f|
      say "  #{f.subject_type.ljust(12)} #{(f.request_type || '(catch-all)').ljust(28)} #{f.summary}"
    end
  end

  # Requests that predate the chain get approval rows matching where they
  # already are, so the admin panel and the tracker app agree about them.
  def backfill_existing
    created = 0
    EditRequest.includes(:approvals).find_each do |req|
      next if req.approvals.any?

      req.build_approvals!
      req.reload

      req.approvals.each do |approval|
        case req.status
        when "approved"
          approval.update!(status: "approved", acted_at: req.resolved_at || req.updated_at)
        when "rejected"
          approval.update!(status: "rejected", acted_at: req.resolved_at || req.updated_at)
        else
          # Still pending: the manager step is settled if they already signed
          # off, but the admin step stays pending - an admin has not acted, and
          # under the old flow that is exactly what the request was waiting for.
          if req.approved_by_manager? && !approval.approval_step.admin_step?
            approval.update!(status: "approved", acted_at: req.updated_at)
          end
        end
      end
      created += req.approvals.size
    end

    pending = EditRequest.where(status: "pending").includes(approvals: { approval_step: :role }).to_a
    waiting = pending.group_by { |r| r.current_step&.to_s || "nothing (chain complete)" }

    say ""
    say "Backfilled #{created} approval rows across #{EditRequest.count} edit requests."
    say "  #{pending.size} pending requests are waiting on:"
    waiting.sort_by { |k, v| -v.size }.each { |step, rs| say "    #{step.to_s.ljust(24)} #{rs.size}" }
  end

  # Same idea as backfill_existing, but for leaves: they only have
  # approved_by_manager/status to infer past state from (no admin flag, no
  # resolved_at), so a decided leave settles every step at once.
  def backfill_existing_leaves
    created = 0
    Leave.includes(:approvals).find_each do |leave|
      next if leave.approvals.any?

      leave.build_approvals!
      leave.reload

      leave.approvals.each do |approval|
        case leave.status
        when "approved"
          approval.update!(status: "approved", acted_at: leave.updated_at)
        when "rejected"
          approval.update!(status: "rejected", acted_at: leave.updated_at)
        else
          if leave.approved_by_manager? && !approval.approval_step.admin_step?
            approval.update!(status: "approved", acted_at: leave.updated_at)
          end
        end
      end
      created += leave.approvals.size
    end

    pending = Leave.where(status: "pending").includes(approvals: { approval_step: :role }).to_a
    waiting = pending.group_by { |l| l.current_step&.to_s || "nothing (chain complete)" }

    say ""
    say "Backfilled #{created} approval rows across #{Leave.count} leaves."
    say "  #{pending.size} pending leaves are waiting on:"
    waiting.sort_by { |k, v| -v.size }.each { |step, rs| say "    #{step.to_s.ljust(24)} #{rs.size}" }
  end
end

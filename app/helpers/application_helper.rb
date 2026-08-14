module ApplicationHelper
  # Both counts are scoped by the organogram (everyone below you in the
  # reporting tree) and gated by the role's page permissions, replacing the
  # old hardcoded role/department lists.
  def edit_requests_count
    return 0 unless can_view?("edit_requests.review")

    EditRequest.where(user_id: reviewable_user_ids).count
  end

  def leaves_count
    return 0 unless can_view?("leaves.review")

    Leave.where(user_id: reviewable_user_ids).count
  end

  private

  def reviewable_user_ids
    @reviewable_user_ids ||= current_user.subordinate_ids
  end
end

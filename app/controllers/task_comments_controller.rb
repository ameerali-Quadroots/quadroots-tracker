# The task discussion thread. Every action here is reached over fetch() from
# the task drawer and answers with JSON carrying rendered HTML, so the drawer
# never has to re-render itself to show one new comment.
class TaskCommentsController < ApplicationController
  include DepartmentTaskScope

  before_action :set_task
  before_action :set_comment, only: %i[update destroy]

  def index
    render json: {
      count: comments.size,
      html: render_to_string(partial: "task_comments/thread",
                             locals: { task: @task, comments: comments }, formats: [:html])
    }
  end

  def create
    comment = @task.comments.new(comment_params.merge(user: current_user))

    if comment.save
      NotificationService.notify_task_comment(comment)
      render json: {
        count: @task.comments.count,
        html: render_to_string(partial: "task_comments/comment",
                               locals: { comment: comment }, formats: [:html])
      }, status: :created
    else
      render json: { error: comment.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def update
    return refuse("You can only edit your own comment, within 15 minutes of posting it.") unless @comment.editable_by?(current_user)

    if @comment.update(comment_params)
      render json: {
        count: @task.comments.count,
        html: render_to_string(partial: "task_comments/comment",
                               locals: { comment: @comment }, formats: [:html])
      }
    else
      render json: { error: @comment.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    return refuse("You can only delete your own comment.") unless @comment.deletable_by?(current_user)

    @comment.destroy
    render json: { count: @task.comments.count, id: @comment.id }
  end

  private

  def comments
    @comments ||= @task.comments.includes(:user).chronological.to_a
  end

  def set_task
    @task = find_visible_task(params[:task_id])
    forbid! if @task.nil?
  end

  def set_comment
    @comment = @task.comments.find_by(id: params[:id])
    return if @comment.present?

    render json: { error: "That comment no longer exists." }, status: :not_found
  end

  def refuse(message)
    render json: { error: message }, status: :forbidden
  end

  def comment_params
    params.require(:task_comment).permit(:body)
  end
end

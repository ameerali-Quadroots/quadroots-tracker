class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def unread
    notifications = current_user.notifications.unread.order(created_at: :desc).to_a
    return render json: [] if notifications.empty?

    data = notifications.map { |n| { title: n.title, message: n.message, url: n.url } }
    Notification.where(id: notifications.map(&:id)).update_all(read_at: Time.current)
    render json: data
  end
end

class PusherController < ApplicationController
  before_action :authenticate_user!
  protect_from_forgery except: :auth

  def auth
    channel_name = params[:channel_name]
    socket_id    = params[:socket_id]

    if channel_name == "private-user-#{current_user.id}"
      response = Pusher.authenticate(channel_name, socket_id)
      render json: response
    else
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
end

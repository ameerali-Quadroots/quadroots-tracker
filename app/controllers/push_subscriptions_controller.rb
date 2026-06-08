class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def create
    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: params[:endpoint])
    sub.assign_attributes(p256dh_key: params.dig(:keys, :p256dh), auth_key: params.dig(:keys, :auth))

    if sub.save
      head :ok
    else
      render json: { error: sub.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    current_user.push_subscriptions.find_by(endpoint: params[:endpoint])&.destroy
    head :ok
  end
end

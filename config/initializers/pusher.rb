if ENV['PUSHER_APP_ID'].present?
  Pusher.app_id  = ENV['PUSHER_APP_ID']
  Pusher.key     = ENV['PUSHER_APP_KEY']
  Pusher.secret  = ENV['PUSHER_APP_SECRET']
  Pusher.cluster = ENV['PUSHER_APP_CLUSTER']
  Pusher.logger  = Rails.logger
end

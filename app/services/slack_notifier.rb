require "net/http"
require "uri"
require "json"

# Sends a Slack DM by looking up the recipient's Slack account from their
# email (users.lookupByEmail), then posting to that user's DM channel.
# Ported from task_manager/app/services/slack_notifier.rb, with the bot
# token moved out of source into ENV["SLACK_BOT_TOKEN"] (.env, gitignored).
class SlackNotifier
  SLACK_API_URL = "https://slack.com/api"

  def self.notify(message, email:)
    token = ENV["SLACK_BOT_TOKEN"]
    if token.blank?
      Rails.logger.warn("[Slack] SLACK_BOT_TOKEN not set. Skipping notification.")
      return
    end

    unless email.present?
      Rails.logger.warn("[Slack] No email provided. Skipping notification.")
      return
    end

    user_id = find_user_id_by_email(email, token)
    unless user_id
      Rails.logger.warn("[Slack] Could not find Slack user for email: #{email}")
      return
    end

    uri = URI.parse("#{SLACK_API_URL}/chat.postMessage")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = { channel: user_id, text: message }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    body = JSON.parse(response.body)
    if body["ok"]
      Rails.logger.info("[Slack] DM sent successfully to #{email} (#{user_id})")
    else
      Rails.logger.error("[Slack] Failed to send DM: #{body['error']}")
    end
  rescue SocketError, Errno::ECONNREFUSED => e
    Rails.logger.error("[Slack] Network error: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[Slack] Error sending DM: #{e.message}")
  end

  def self.find_user_id_by_email(email, token)
    uri = URI.parse("#{SLACK_API_URL}/users.lookupByEmail?email=#{URI.encode_www_form_component(email)}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    body = JSON.parse(response.body)
    if body["ok"]
      body["user"]["id"]
    else
      Rails.logger.warn("[Slack] Could not find user by email #{email}: #{body['error']}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("[Slack] Error finding user by email: #{e.message}")
    nil
  end
  private_class_method :find_user_id_by_email
end

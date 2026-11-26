# frozen_string_literal: true

require "digest"
require "warden"

Warden::Strategies.add(:api_token) do
  def valid?
    expected_token.present? && secure_token_match?(extracted_bearer, expected_token)
  end

  def authenticate!
    success!(Auth::Principal.service)
  end

  private

  def extracted_bearer
    header = request.get_header("HTTP_AUTHORIZATION")
    return nil unless header&.start_with?("Bearer ")

    header.delete_prefix("Bearer ").strip
  end

  def expected_token
    ENV["RPGCLUB_BOT_API_TOKEN"]
  end

  def secure_token_match?(given, expected)
    return false if given.blank? || expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(given),
      Digest::SHA256.hexdigest(expected)
    )
  end
end

# The versioning job's narrow token (spec api#510, ticket api#514): it may
# only report Pending Changes. ApplicationController never tries it, so it
# signs nobody in anywhere else; PendingChangesController#create asks for it
# by name. Its principal is neither the service nor a Discord user.
Warden::Strategies.add(:release_token) do
  def valid?
    expected = ENV["RPGCLUB_RELEASE_API_TOKEN"]
    header = request.get_header("HTTP_AUTHORIZATION")
    return false if expected.blank? || !header&.start_with?("Bearer ")

    given = header.delete_prefix("Bearer ").strip
    given.present? && ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(given), Digest::SHA256.hexdigest(expected)
    )
  end

  def authenticate!
    success!(Auth::Principal.release)
  end
end

Warden::Strategies.add(:user_session_token) do
  def valid?
    bearer_token.present?
  end

  def authenticate!
    user = UserSessionToken.authenticated_user(bearer_token)
    if user
      success!(Auth::Principal.discord_user(
        user,
        { "avatar" => user.discord_avatar },
        is_dev: user.read_attribute(:session_is_dev),
        is_longstanding: user.read_attribute(:session_is_longstanding)
      ))
    else
      fail!("Invalid or expired session token")
    end
  end

  private

  def bearer_token
    header = request.get_header("HTTP_AUTHORIZATION")
    return nil unless header&.start_with?("Bearer ")

    header.delete_prefix("Bearer ").strip
  end
end

Rails.application.config.middleware.use Warden::Manager do |manager|
  manager.intercept_401 = false

  manager.failure_app = lambda do |_env|
    [
      401,
      { "Content-Type" => "application/json" },
      [ { error: "unauthorized" }.to_json ]
    ]
  end

  manager.serialize_into_session do |principal|
    principal.to_session if principal.respond_to?(:discord_user?) && principal.discord_user?
  end

  manager.serialize_from_session do |payload|
    Auth::Principal.from_session(payload)
  end
end

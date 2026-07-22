# frozen_string_literal: true

# The api_token warden strategy compares the bearer against this env var at
# request time, so give the test environment a stable known value.
ENV["RPGCLUB_BOT_API_TOKEN"] ||= "test-service-token"

# Request-spec helpers for the two authentication modes (see
# config/initializers/warden.rb): the bot service token and a user session
# token issued after Discord OAuth.
module AuthHelpers
  # Headers authenticating as the bot service principal.
  def service_headers
    { "Authorization" => "Bearer #{ENV.fetch('RPGCLUB_BOT_API_TOKEN')}" }
  end

  # Headers authenticating as `user` via a freshly issued session token.
  def auth_headers_for(user, is_dev: false, is_longstanding: false)
    raw_token = UserSessionToken.generate_for(user, is_dev: is_dev, is_longstanding: is_longstanding)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  def json
    response.parsed_body
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end

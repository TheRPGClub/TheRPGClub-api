# frozen_string_literal: true

require "faraday"

module Auth
  class DiscordOauthClient
    class ConfigurationError < StandardError; end
    class GuildMembershipError < StandardError; end

    AUTHORIZE_URL = "https://discord.com/oauth2/authorize"
    TOKEN_URL = "https://discord.com/api/oauth2/token"
    USER_URL = "https://discord.com/api/users/@me"
    USER_GUILDS_URL = "https://discord.com/api/users/@me/guilds"
    USER_GUILD_MEMBER_URL = "https://discord.com/api/users/@me/guilds/%<guild_id>s/member"

    def authorization_url(state:, redirect_uri:)
      query = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: oauth_scopes.join(" "),
        state: state,
        prompt: "none"
      }.to_query

      "#{AUTHORIZE_URL}?#{query}"
    end

    def exchange_code!(code:, redirect_uri:)
      response = Faraday.post(TOKEN_URL) do |request|
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = {
          client_id: client_id,
          client_secret: client_secret,
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri
        }.to_query
      end

      parse_response!(response)
    end

    def ensure_rpgclub_member!(access_token, discord_user_id: nil)
      ensure_guilds_scope!

      log_guild_membership_check("checking", discord_user_id: discord_user_id)
      guilds = fetch_current_user_guilds!(access_token)
      guild_count = guilds.size

      if guilds.any? { |guild| guild.fetch("id", nil).to_s == rpgclub_guild_id }
        log_guild_membership_check("confirmed", discord_user_id: discord_user_id, guild_count: guild_count)
        return true
      end

      log_guild_membership_check("denied", discord_user_id: discord_user_id, guild_count: guild_count, level: :warn)

      raise GuildMembershipError, "Discord user is not a member of TheRPGClub Discord server"
    end

    def fetch_user!(access_token)
      response = Faraday.get(USER_URL) do |request|
        request.headers["Authorization"] = "Bearer #{access_token}"
      end

      parse_response!(response)
    end

    def fetch_rpgclub_member_roles!(access_token)
      ensure_guild_members_read_scope!
      url = format(USER_GUILD_MEMBER_URL, guild_id: rpgclub_guild_id)
      response = Faraday.get(url) do |request|
        request.headers["Authorization"] = "Bearer #{access_token}"
      end
      payload = parse_response!(response)
      Array(payload["roles"]).map(&:to_s)
    end

    private

    def fetch_current_user_guilds!(access_token)
      response = Faraday.get(USER_GUILDS_URL) do |request|
        request.headers["Authorization"] = "Bearer #{access_token}"
      end

      parse_response!(response)
    end

    def log_guild_membership_check(outcome, discord_user_id:, guild_count: nil, level: :info)
      payload = {
        event: "discord_oauth.guild_membership_check",
        outcome: outcome,
        discord_user_id: sanitized_discord_user_id(discord_user_id)
      }
      payload[:guild_count] = guild_count unless guild_count.nil?

      Rails.logger.public_send(level, payload.to_json)
    end

    def sanitized_discord_user_id(discord_user_id)
      value = discord_user_id.to_s.strip
      return value if value.match?(/\A\d+\z/)

      "unknown"
    end

    def client_id
      value = ENV.fetch("DISCORD_CLIENT_ID", nil).to_s.strip
      return value if value.match?(/\A\d+\z/)

      raise ConfigurationError, "DISCORD_CLIENT_ID must be the numeric Discord application client ID"
    end

    def client_secret
      value = ENV.fetch("DISCORD_CLIENT_SECRET", nil).to_s.strip
      return value if value.present? && value != "change_me"

      raise ConfigurationError, "DISCORD_CLIENT_SECRET must be set from the Discord application OAuth2 settings"
    end

    def rpgclub_guild_id
      value = ENV.fetch("DISCORD_RPGCLUB_GUILD_ID", nil).to_s.strip
      return value if value.match?(/\A\d+\z/)

      raise ConfigurationError, "DISCORD_RPGCLUB_GUILD_ID must be the numeric TheRPGClub Discord server ID"
    end

    def oauth_scopes
      ENV.fetch("DISCORD_OAUTH_SCOPES", "identify email guilds guilds.members.read").split
    end

    def ensure_guilds_scope!
      return if oauth_scopes.include?("guilds")

      raise ConfigurationError, "DISCORD_OAUTH_SCOPES must include guilds to verify TheRPGClub membership"
    end

    def ensure_guild_members_read_scope!
      return if oauth_scopes.include?("guilds.members.read")

      raise ConfigurationError, "DISCORD_OAUTH_SCOPES must include guilds.members.read to read guild member roles"
    end

    def parse_response!(response)
      payload = JSON.parse(response.body)
      return payload if response.success?

      raise StandardError, discord_error_message(payload)
    rescue JSON::ParserError
      raise StandardError, "Discord OAuth request failed with HTTP #{response.status}"
    end

    def discord_error_message(payload)
      [
        payload["error_description"],
        payload["message"],
        payload["error"],
        nested_error_messages(payload["errors"])
      ].compact_blank.join(": ").presence || "Discord OAuth request failed"
    end

    def nested_error_messages(errors)
      return if errors.blank?

      errors.to_json
    end
  end
end

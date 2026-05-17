# frozen_string_literal: true

module Auth
  class DiscordController < ActionController::API
    def start
      session[:discord_oauth_state] = SecureRandom.hex(24)

      redirect_to oauth_client.authorization_url(
        state: session[:discord_oauth_state],
        redirect_uri: callback_url
      ), allow_other_host: true
    rescue Auth::DiscordOauthClient::ConfigurationError => e
      render json: { error: "discord_oauth_not_configured", detail: e.message }, status: :unprocessable_entity
    end

    def callback
      return render_invalid_state unless valid_state?

      token = oauth_client.exchange_code!(code: params.require(:code), redirect_uri: callback_url)
      access_token = token.fetch("access_token")
      discord_user = oauth_client.fetch_user!(access_token)
      oauth_client.ensure_rpgclub_member!(access_token, discord_user_id: discord_user.fetch("id", nil))
      user = RpgClubUser.upsert_from_discord!(discord_user)

      role_ids = fetch_member_role_ids(access_token)
      is_dev = role_assigned?(role_ids, DiscordRoles::DEV)
      is_longstanding = role_assigned?(role_ids, DiscordRoles::LONGSTANDING)

      request.env["warden"].set_user(
        Auth::Principal.discord_user(user, discord_user, is_dev: is_dev, is_longstanding: is_longstanding)
      )
      session.delete(:discord_oauth_state)

      raw_token = UserSessionToken.generate_for(user, is_dev: is_dev, is_longstanding: is_longstanding)
      redirect_to "#{success_redirect_url}?token=#{CGI.escape(raw_token)}", allow_other_host: true
    rescue Auth::DiscordOauthClient::ConfigurationError => e
      render json: { error: "discord_oauth_not_configured", detail: e.message }, status: :unprocessable_entity
    rescue Auth::DiscordOauthClient::GuildMembershipError => e
      render json: { error: "discord_guild_membership_required", detail: e.message }, status: :forbidden
    rescue ActionController::ParameterMissing, KeyError, StandardError => e
      render json: { error: "discord_oauth_failed", detail: e.message }, status: :unauthorized
    end

    private

    def oauth_client
      @oauth_client ||= Auth::DiscordOauthClient.new
    end

    def callback_url
      ENV.fetch("DISCORD_REDIRECT_URI") { auth_discord_callback_url }
    end

    def success_redirect_url
      ENV.fetch("DISCORD_OAUTH_SUCCESS_REDIRECT", "/api/v1/session")
    end

    def render_invalid_state
      render json: {
        error: "invalid_oauth_state",
        detail: "OAuth session state was missing or mismatched. Start login and callback on the same host, " \
          "for example localhost with localhost or 127.0.0.1 with 127.0.0.1."
      }, status: :unauthorized
    end

    def valid_state?
      params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(
        params[:state].to_s,
        session[:discord_oauth_state].to_s
      )
    end

    def fetch_member_role_ids(access_token)
      oauth_client.fetch_rpgclub_member_roles!(access_token)
    rescue StandardError => e
      Rails.logger.warn({ event: "discord_oauth.member_roles_fetch_failed", error: e.message }.to_json)
      []
    end

    def role_assigned?(role_ids, role_id)
      return false if role_id.to_s.empty?

      role_ids.include?(role_id.to_s)
    end
  end
end

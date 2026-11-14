# frozen_string_literal: true

module Auth
  class DiscordController < ActionController::API
    RETURN_TO_MAX_BYTES = 1024

    # Every outcome of a sign-in lands on the website, so neither step runs
    # without a usable website address.
    before_action :require_website_address

    def start
      session[:discord_oauth_state] = SecureRandom.hex(24)
      session[:discord_oauth_return_to] = safe_return_to(params[:return_to])

      redirect_to oauth_client.authorization_url(
        state: session[:discord_oauth_state],
        redirect_uri: callback_url
      ), allow_other_host: true
    rescue Auth::DiscordOauthClient::ConfigurationError => e
      render_not_configured(e)
    end

    def callback
      unless valid_state?
        return redirect_auth_failed(
          "OAuth session state was missing or mismatched. Start login and callback on the same host, " \
          "for example localhost with localhost or 127.0.0.1 with 127.0.0.1."
        )
      end

      session.delete(:discord_oauth_state)
      return_to = session.delete(:discord_oauth_return_to)
      token = oauth_client.exchange_code!(code: params.require(:code), redirect_uri: callback_url)
      access_token = token.fetch("access_token")
      discord_user = oauth_client.fetch_user!(access_token)
      oauth_client.ensure_rpgclub_member!(access_token, discord_user_id: discord_user.fetch("id", nil))
      user = RpgClubUser.upsert_from_discord!(discord_user)

      role_ids = fetch_member_role_ids(access_token)
      user.apply_discord_roles!(role_ids) unless role_ids.nil?
      is_dev = role_assigned?(role_ids, DiscordRoles::DEV)
      is_longstanding = role_assigned?(role_ids, DiscordRoles::LONGSTANDING)

      request.env["warden"].set_user(
        Auth::Principal.discord_user(user, discord_user, is_dev: is_dev, is_longstanding: is_longstanding)
      )
      raw_token = UserSessionToken.generate_for(user, is_dev: is_dev, is_longstanding: is_longstanding)
      redirect_to success_url(token: raw_token, return_to: return_to), allow_other_host: true
    rescue Auth::DiscordOauthClient::ConfigurationError => e
      render_not_configured(e)
    rescue Auth::DiscordOauthClient::GuildMembershipError
      redirect_to website_url("/join", return_to: return_to), allow_other_host: true
    rescue StandardError => e
      redirect_auth_failed(e.message)
    end

    private

    def oauth_client
      @oauth_client ||= Auth::DiscordOauthClient.new
    end

    def callback_url
      ENV.fetch("DISCORD_REDIRECT_URI") { auth_discord_callback_url }
    end

    def render_not_configured(error)
      render json: { error: "discord_oauth_not_configured", detail: error.message }, status: :unprocessable_entity
    end

    def require_website_address
      website_address
    rescue Auth::DiscordOauthClient::ConfigurationError => e
      render_not_configured(e)
    end

    # The success destination, DISCORD_OAUTH_SUCCESS_REDIRECT, is the website's
    # sign-in callback and its origin is the website. It must be an absolute
    # http(s) URL: a missing or relative setting would land the other outcomes
    # on the API's own host. Checked before each step (see
    # require_website_address), so the URL helpers below never raise, even
    # from the callback's rescue clauses.
    def website_address
      @website_address ||= begin
        uri = URI.parse(ENV.fetch("DISCORD_OAUTH_SUCCESS_REDIRECT", ""))
        raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.host.present?

        uri
      rescue URI::InvalidURIError
        raise Auth::DiscordOauthClient::ConfigurationError,
          "DISCORD_OAUTH_SUCCESS_REDIRECT must be the website's absolute sign-in callback URL, " \
          "for example http://localhost:3001/auth/callback"
      end
    end

    # A return-to is only ever a same-origin path on the website. A single
    # leading slash rules out a scheme or host ("//host" is protocol-relative);
    # backslashes and control characters are refused because browsers read
    # "/\host" as "//host" and drop tabs and newlines ("/\t/host"). It is
    # capped at 1 KB as stored, so it cannot overflow the ~4 KB cookie-stored
    # session: the cap counts the JSON-encoded bytes because the session
    # escapes some characters ("<" becomes "\u003c") and a multi-byte
    # character is several bytes. Anything else is discarded rather than
    # repaired.
    def safe_return_to(value)
      return nil unless value.is_a?(String) && value.to_json.bytesize <= RETURN_TO_MAX_BYTES
      return nil unless value.start_with?("/") && !value.start_with?("//")
      return nil if value.include?("\\") || value.match?(/[[:cntrl:]]/)

      value
    end

    # The success destination with the sign-in result added to any query it
    # already carries.
    def success_url(**query)
      uri = website_address.dup
      uri.query = [ uri.query.presence, query.compact.to_query.presence ].compact.join("&").presence
      uri.to_s
    end

    # Pages on the website live at the origin of the success destination, which
    # is the website's front page or its sign-in callback.
    def website_url(path, **query)
      uri = website_address.dup
      uri.path = path
      uri.query = query.compact.to_query.presence
      uri.fragment = nil
      uri.to_s
    end

    # Every sign-in failure lands back on the website's front page, which shows
    # a plain message and a way to try again. The detail stays in the log.
    def redirect_auth_failed(detail)
      Rails.logger.warn({ event: "discord_oauth.failed", detail: detail }.to_json)
      redirect_to website_url("/", error: "auth_failed"), allow_other_host: true
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
      # nil (not []) so a failed fetch keeps the stored role flags instead of
      # stripping a member's staff roles because Discord hiccuped.
      Rails.logger.warn({ event: "discord_oauth.member_roles_fetch_failed", error: e.message }.to_json)
      nil
    end

    def role_assigned?(role_ids, role_id)
      return false if role_id.to_s.empty? || role_ids.nil?

      role_ids.include?(role_id.to_s)
    end
  end
end

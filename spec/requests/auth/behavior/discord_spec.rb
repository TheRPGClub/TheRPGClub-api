# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Discord OAuth flow (Auth::DiscordController): the
# /auth/discord start redirect and the /auth/discord/callback code exchange.
#
# Auth::DiscordOauthClient talks to Discord over Faraday, so callback examples
# stub the client at the controller's own seam (Auth::DiscordOauthClient.new)
# — no example ever performs a real HTTP call. The start examples use the real
# client: building the authorization URL is pure string work, no network.
RSpec.describe "auth/discord behavior", type: :request do
  # Set (and afterwards restore) ENV keys for the duration of a block so the
  # examples neither depend on ambient .env values nor leak overrides.
  def with_env(overrides)
    saved = overrides.keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe "GET /auth/discord" do
    around do |example|
      with_env(
        "DISCORD_CLIENT_ID" => "123456789012345678",
        "DISCORD_OAUTH_SCOPES" => "identify email guilds guilds.members.read",
        "DISCORD_REDIRECT_URI" => "http://localhost:3000/auth/discord/callback",
        "DISCORD_OAUTH_SUCCESS_REDIRECT" => "https://front.test/auth/callback"
      ) { example.run }
    end

    it "redirects to Discord's authorization URL with a CSRF state" do
      get "/auth/discord"

      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("https://discord.com/oauth2/authorize?")

      query = Rack::Utils.parse_query(URI.parse(response.location).query)
      expect(query).to include(
        "client_id" => "123456789012345678",
        "redirect_uri" => "http://localhost:3000/auth/discord/callback",
        "response_type" => "code",
        "scope" => "identify email guilds guilds.members.read"
      )
      expect(query.fetch("state")).to be_present
    end

    context "when the Discord client id is not configured" do
      around { |example| with_env("DISCORD_CLIENT_ID" => "") { example.run } }

      it "renders the documented 422 configuration error" do
        get "/auth/discord"

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("discord_oauth_not_configured")
        expect(json.fetch("detail")).to include("DISCORD_CLIENT_ID")
      end
    end

    {
      "missing" => nil,
      "relative" => "/api/v1/session",
      "malformed" => "https://front test/auth/callback"
    }.each do |label, setting|
      context "when the website address is #{label}" do
        around { |example| with_env("DISCORD_OAUTH_SUCCESS_REDIRECT" => setting) { example.run } }

        it "renders the 422 configuration error instead of sending the Visitor to Discord" do
          get "/auth/discord"

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.fetch("error")).to eq("discord_oauth_not_configured")
          expect(json.fetch("detail")).to include("DISCORD_OAUTH_SUCCESS_REDIRECT")
        end
      end
    end
  end

  describe "GET /auth/discord/callback" do
    let(:client) { instance_double(Auth::DiscordOauthClient) }
    let(:discord_id) { SecureRandom.random_number(10**18).to_s }
    let(:discord_user_payload) do
      {
        "id" => discord_id,
        "username" => "oauth_user",
        "global_name" => "OAuth User",
        "avatar" => "a1b2c3avatarhash",
        "email" => "oauth_user@example.com"
      }
    end

    around do |example|
      with_env(
        "DISCORD_REDIRECT_URI" => "http://localhost:3000/auth/discord/callback",
        "DISCORD_OAUTH_SUCCESS_REDIRECT" => "https://front.test/auth/callback"
      ) { example.run }
    end

    before { allow(Auth::DiscordOauthClient).to receive(:new).and_return(client) }

    # GET /auth/discord (with the stubbed client) so the session holds a CSRF
    # state, returning the state the controller generated.
    def begin_oauth(return_to: nil)
      captured_state = nil
      allow(client).to receive(:authorization_url) do |**kwargs|
        captured_state = kwargs.fetch(:state)
        "https://discord.com/oauth2/authorize?state=#{captured_state}"
      end

      get "/auth/discord", params: { return_to: return_to }.compact
      captured_state
    end

    def stub_successful_oauth(roles: [])
      allow(client).to receive_messages(
        exchange_code!: { "access_token" => "discord-access-token" },
        fetch_user!: discord_user_payload,
        ensure_rpgclub_member!: true,
        fetch_rpgclub_member_roles!: roles
      )
    end

    def redirect_query
      Rack::Utils.parse_query(URI.parse(response.location).query)
    end

    def token_from_redirect
      redirect_query.fetch("token")
    end

    it "creates the user, issues a session token, and redirects with the token" do
      stub_successful_oauth
      state = begin_oauth

      expect {
        get "/auth/discord/callback", params: { code: "good-code", state: state }
      }.to change(RpgClubUser.where(user_id: discord_id), :count).by(1)
        .and change(UserSessionToken, :count).by(1)

      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("https://front.test/auth/callback?token=")

      session_token = UserSessionToken.find_valid(token_from_redirect)
      expect(session_token).to be_present
      expect(session_token.user_id).to eq(discord_id)
      expect(session_token.is_dev).to be(false)
      expect(session_token.is_longstanding).to be(false)
    end

    it "carries the return-to given at start through to the success redirect" do
      stub_successful_oauth
      state = begin_oauth(return_to: "/games/42?tab=reviews")

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response.location).to start_with("https://front.test/auth/callback?")
      expect(redirect_query.fetch("return_to")).to eq("/games/42?tab=reviews")
      expect(UserSessionToken.find_valid(redirect_query.fetch("token"))).to be_present
    end

    context "when the success destination carries its own query" do
      around do |example|
        with_env("DISCORD_OAUTH_SUCCESS_REDIRECT" => "https://front.test/auth/callback?via=discord") { example.run }
      end

      it "adds the token and return-to to that query" do
        stub_successful_oauth
        state = begin_oauth(return_to: "/games/42")

        get "/auth/discord/callback", params: { code: "good-code", state: state }

        expect(response.location).to start_with("https://front.test/auth/callback?via=discord&")
        expect(response.location.count("?")).to eq(1)
        expect(redirect_query).to include("via" => "discord", "return_to" => "/games/42")
        expect(UserSessionToken.find_valid(redirect_query.fetch("token"))).to be_present
      end
    end

    {
      "protocol-relative" => "//evil.example/games",
      "absolute URL" => "https://evil.example/games",
      "scheme" => "javascript:alert(1)",
      "backslash" => "/\\evil.example/games",
      "relative path" => "games/42",
      "whitespace smuggling" => "/\t/evil.example"
    }.each do |label, unsafe|
      it "discards an unsafe return-to (#{label})" do
        stub_successful_oauth
        state = begin_oauth(return_to: unsafe)

        get "/auth/discord/callback", params: { code: "good-code", state: state }

        expect(response.location).to start_with("https://front.test/auth/callback?")
        expect(redirect_query).not_to have_key("return_to")
        expect(redirect_query.fetch("token")).to be_present
      end
    end

    it "discards an overlong return-to rather than overflowing the session cookie" do
      stub_successful_oauth
      state = begin_oauth(return_to: "/games?q=#{'a' * 3000}")

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response).to have_http_status(:found)
      expect(redirect_query).not_to have_key("return_to")
    end

    it "keeps a return-to just under the 1 KB cap" do
      stub_successful_oauth
      near_cap = "/games?q=#{'a' * 1000}"
      state = begin_oauth(return_to: near_cap)

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(redirect_query.fetch("return_to")).to eq(near_cap)
    end

    {
      "multi-byte characters" => "/#{'🎲' * 2000}",
      "characters the session escapes" => "/#{'<' * 2000}",
      "escaped characters within 1 KB" => "/#{'<' * 1000}"
    }.each do |label, overlong|
      it "discards an over-long return-to of #{label} without failing the start" do
        stub_successful_oauth
        state = begin_oauth(return_to: overlong)

        expect(response).to have_http_status(:found)

        get "/auth/discord/callback", params: { code: "good-code", state: state }

        expect(response.location).to start_with("https://front.test/auth/callback?")
        expect(redirect_query).not_to have_key("return_to")
      end
    end

    it "keeps a percent-encoded return-to path as given" do
      stub_successful_oauth
      state = begin_oauth(return_to: "/games/caf%C3%A9?tab=reviews")

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(redirect_query.fetch("return_to")).to eq("/games/caf%C3%A9?tab=reviews")
    end

    it "keeps a non-ASCII return-to path as given" do
      stub_successful_oauth
      state = begin_oauth(return_to: "/games/café?tab=críticas")

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(redirect_query.fetch("return_to")).to eq("/games/café?tab=críticas")
    end

    it "stores the Discord profile on the upserted user" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      user = RpgClubUser.find_by!(user_id: discord_id)
      expect(user.username).to eq("oauth_user")
      expect(user.global_name).to eq("OAuth User")
      expect(user.discord_avatar).to eq("a1b2c3avatarhash")
    end

    it "exchanges the submitted code against the configured redirect URI" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(client).to have_received(:exchange_code!)
        .with(code: "good-code", redirect_uri: "http://localhost:3000/auth/discord/callback")
      expect(client).to have_received(:fetch_user!).with("discord-access-token")
      expect(client).to have_received(:ensure_rpgclub_member!)
        .with("discord-access-token", discord_user_id: discord_id)
    end

    it "issues a token that authenticates subsequent API calls" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      token = token_from_redirect

      # Fresh integration session: prove the bearer token alone authenticates,
      # not the warden cookie set during the callback.
      reset!

      get "/api/v1/session", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      expect(json.dig("principal", "id")).to eq(discord_id)
    end

    it "flags the session token dev/longstanding from the member's guild roles" do
      stub_successful_oauth(roles: [ DiscordRoles::DEV, DiscordRoles::LONGSTANDING, "42" ])
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      session_token = UserSessionToken.find_valid(token_from_redirect)
      expect(session_token.is_dev).to be(true)
      expect(session_token.is_longstanding).to be(true)
    end

    it "writes the staff and member role flags from the member's guild roles" do
      stub_successful_oauth(roles: [ "461891227613265940", "267881447258325002", "267883288817958912",
                                     "747520789003239530", "42" ])
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      token = token_from_redirect
      reset!
      get "/api/v1/session", headers: { "Authorization" => "Bearer #{token}" }

      expect(json.fetch("membership")).to include(
        "admin" => true, "moderator" => true, "regular" => true, "member" => true
      )
    end

    it "stores the dev role, so the bot's Feature access lookup sees the Superadmin" do
      stub_successful_oauth(roles: [ DiscordRoles::DEV ])
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      reset!
      get "/api/v1/users/#{discord_id}/feature_access", headers: service_headers

      expect(json.dig("data", "staff")).to be(true)
    end

    it "clears role flags the member no longer holds at sign-in" do
      create(:user, :admin, user_id: discord_id, role_moderator: true, role_regular: true, role_member: true)
      stub_successful_oauth(roles: [ "747520789003239530" ])
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      token = token_from_redirect
      reset!
      get "/api/v1/session", headers: { "Authorization" => "Bearer #{token}" }

      expect(json.fetch("membership")).to include(
        "admin" => false, "moderator" => false, "regular" => false, "member" => true
      )
    end

    it "keeps the stored role flags when the roles fetch fails" do
      create(:user, :admin, user_id: discord_id, role_member: true)
      allow(client).to receive_messages(
        exchange_code!: { "access_token" => "discord-access-token" },
        fetch_user!: discord_user_payload,
        ensure_rpgclub_member!: true
      )
      allow(client).to receive(:fetch_rpgclub_member_roles!).and_raise(StandardError, "discord is down")
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      token = token_from_redirect
      reset!
      get "/api/v1/session", headers: { "Authorization" => "Bearer #{token}" }

      expect(json.fetch("membership")).to include("admin" => true, "member" => true)
    end

    it "updates the existing user record instead of creating a duplicate" do
      create(:user, user_id: discord_id, username: "stale_name")
      stub_successful_oauth
      state = begin_oauth

      expect {
        get "/auth/discord/callback", params: { code: "good-code", state: state }
      }.not_to change(RpgClubUser, :count)

      user = RpgClubUser.find_by!(user_id: discord_id)
      expect(user.username).to eq("oauth_user")
      expect(user.global_name).to eq("OAuth User")
    end

    it "still logs the member in with no role flags when the roles fetch fails" do
      allow(client).to receive_messages(
        exchange_code!: { "access_token" => "discord-access-token" },
        fetch_user!: discord_user_payload,
        ensure_rpgclub_member!: true
      )
      allow(client).to receive(:fetch_rpgclub_member_roles!).and_raise(StandardError, "discord is down")
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response).to have_http_status(:found)
      session_token = UserSessionToken.find_valid(token_from_redirect)
      expect(session_token.is_dev).to be(false)
      expect(session_token.is_longstanding).to be(false)
    end

    it "redirects to the website's auth-failed destination when the callback arrives without a prior start" do
      get "/auth/discord/callback", params: { code: "good-code", state: "forged-state" }

      expect(response).to redirect_to("https://front.test/?error=auth_failed")
      expect(UserSessionToken.count).to eq(0)
    end

    it "redirects to the auth-failed destination when the state does not match the one issued at start" do
      stub_successful_oauth
      begin_oauth(return_to: "/games/42")

      get "/auth/discord/callback", params: { code: "good-code", state: "tampered" }

      expect(response).to redirect_to("https://front.test/?error=auth_failed")
      expect(UserSessionToken.count).to eq(0)
    end

    it "redirects to the auth-failed destination when the state parameter is missing" do
      stub_successful_oauth
      begin_oauth

      get "/auth/discord/callback", params: { code: "good-code" }

      expect(response).to redirect_to("https://front.test/?error=auth_failed")
    end

    it "consumes the state on success, so replaying the callback fails" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      expect(response.location).to start_with("https://front.test/auth/callback?")

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response).to redirect_to("https://front.test/?error=auth_failed")
    end

    it "redirects to the auth-failed destination when the code exchange is rejected" do
      allow(client).to receive(:exchange_code!)
        .and_raise(StandardError, 'invalid_grant: Invalid "code" in request.')
      state = begin_oauth(return_to: "/games/42")

      get "/auth/discord/callback", params: { code: "bad-code", state: state }

      expect(response).to redirect_to("https://front.test/?error=auth_failed")
      expect(UserSessionToken.count).to eq(0)
    end

    it "redirects to the auth-failed destination when Discord sends no code (consent denied)" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { error: "access_denied", state: state }

      expect(response).to redirect_to("https://front.test/?error=auth_failed")
    end

    context "when the Visitor is not in the club's Discord server" do
      before do
        allow(client).to receive_messages(
          exchange_code!: { "access_token" => "discord-access-token" },
          fetch_user!: discord_user_payload
        )
        allow(client).to receive(:ensure_rpgclub_member!)
          .and_raise(Auth::DiscordOauthClient::GuildMembershipError,
            "Discord user is not a member of TheRPGClub Discord server")
      end

      it "redirects to the website's join page with the return-to, issuing no token" do
        state = begin_oauth(return_to: "/games/42?tab=reviews")

        get "/auth/discord/callback", params: { code: "good-code", state: state }

        expect(response).to have_http_status(:found)
        expect(response.location).to start_with("https://front.test/join?")
        expect(redirect_query).to eq("return_to" => "/games/42?tab=reviews")
        expect(RpgClubUser.where(user_id: discord_id)).not_to exist
        expect(UserSessionToken.count).to eq(0)
      end

      it "redirects to the bare join page when no return-to was given" do
        state = begin_oauth

        get "/auth/discord/callback", params: { code: "good-code", state: state }

        expect(response.location).to eq("https://front.test/join")
      end
    end

    # A sign-in already under way when the website address breaks (a deploy
    # between start and callback) ends in the 422 configuration error, never a
    # 500 or a redirect onto the API's own host.
    context "when the website address is broken by the time Discord calls back" do
      def call_back_with_website_address(setting, **params)
        with_env("DISCORD_OAUTH_SUCCESS_REDIRECT" => setting) do
          get "/auth/discord/callback", params: params
        end
      end

      {
        "missing" => nil,
        "relative" => "/api/v1/session",
        "malformed" => "https://front test/auth/callback"
      }.each do |label, setting|
        it "422s on success, issuing no token (#{label})" do
          stub_successful_oauth
          state = begin_oauth

          call_back_with_website_address(setting, code: "good-code", state: state)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.fetch("error")).to eq("discord_oauth_not_configured")
          expect(json.fetch("detail")).to include("DISCORD_OAUTH_SUCCESS_REDIRECT")
          expect(UserSessionToken.count).to eq(0)
        end

        it "422s when the sign-in fails (#{label})" do
          allow(client).to receive(:exchange_code!).and_raise(StandardError, "invalid_grant")
          state = begin_oauth

          call_back_with_website_address(setting, code: "bad-code", state: state)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.fetch("error")).to eq("discord_oauth_not_configured")
        end

        it "422s when the state does not match (#{label})" do
          call_back_with_website_address(setting, code: "good-code", state: "forged-state")

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.fetch("error")).to eq("discord_oauth_not_configured")
        end

        it "422s when the Visitor is not in the club's Discord server (#{label})" do
          allow(client).to receive_messages(
            exchange_code!: { "access_token" => "discord-access-token" },
            fetch_user!: discord_user_payload
          )
          allow(client).to receive(:ensure_rpgclub_member!)
            .and_raise(Auth::DiscordOauthClient::GuildMembershipError, "not a member")
          state = begin_oauth(return_to: "/games/42")

          call_back_with_website_address(setting, code: "good-code", state: state)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.fetch("error")).to eq("discord_oauth_not_configured")
        end
      end
    end

    it "422s with discord_oauth_not_configured when the client is misconfigured" do
      allow(client).to receive(:exchange_code!)
        .and_raise(Auth::DiscordOauthClient::ConfigurationError,
          "DISCORD_CLIENT_SECRET must be set from the Discord application OAuth2 settings")
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("discord_oauth_not_configured")
    end
  end
end

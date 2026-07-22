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
        "DISCORD_REDIRECT_URI" => "http://localhost:3000/auth/discord/callback"
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
        "DISCORD_OAUTH_SUCCESS_REDIRECT" => "https://front.test/auth/complete"
      ) { example.run }
    end

    before { allow(Auth::DiscordOauthClient).to receive(:new).and_return(client) }

    # GET /auth/discord (with the stubbed client) so the session holds a CSRF
    # state, returning the state the controller generated.
    def begin_oauth
      captured_state = nil
      allow(client).to receive(:authorization_url) do |**kwargs|
        captured_state = kwargs.fetch(:state)
        "https://discord.com/oauth2/authorize?state=#{captured_state}"
      end

      get "/auth/discord"
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

    def token_from_redirect
      Rack::Utils.parse_query(URI.parse(response.location).query).fetch("token")
    end

    it "creates the user, issues a session token, and redirects with the token" do
      stub_successful_oauth
      state = begin_oauth

      expect {
        get "/auth/discord/callback", params: { code: "good-code", state: state }
      }.to change(RpgClubUser.where(user_id: discord_id), :count).by(1)
        .and change(UserSessionToken, :count).by(1)

      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("https://front.test/auth/complete?token=")

      session_token = UserSessionToken.find_valid(token_from_redirect)
      expect(session_token).to be_present
      expect(session_token.user_id).to eq(discord_id)
      expect(session_token.is_dev).to be(false)
      expect(session_token.is_longstanding).to be(false)
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

    it "401s with invalid_oauth_state when the callback arrives without a prior start" do
      get "/auth/discord/callback", params: { code: "good-code", state: "forged-state" }

      expect(response).to have_http_status(:unauthorized)
      expect(json.fetch("error")).to eq("invalid_oauth_state")
      expect(UserSessionToken.count).to eq(0)
    end

    it "401s when the state does not match the one issued at start" do
      stub_successful_oauth
      begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: "tampered" }

      expect(response).to have_http_status(:unauthorized)
      expect(json.fetch("error")).to eq("invalid_oauth_state")
      expect(UserSessionToken.count).to eq(0)
    end

    it "401s when the state parameter is missing" do
      stub_successful_oauth
      begin_oauth

      get "/auth/discord/callback", params: { code: "good-code" }

      expect(response).to have_http_status(:unauthorized)
      expect(json.fetch("error")).to eq("invalid_oauth_state")
    end

    it "consumes the state on success, so replaying the callback 401s" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }
      expect(response).to have_http_status(:found)

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response).to have_http_status(:unauthorized)
      expect(json.fetch("error")).to eq("invalid_oauth_state")
    end

    it "401s with discord_oauth_failed when the code exchange is rejected" do
      allow(client).to receive(:exchange_code!)
        .and_raise(StandardError, 'invalid_grant: Invalid "code" in request.')
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "bad-code", state: state }

      expect(response).to have_http_status(:unauthorized)
      expect(json.fetch("error")).to eq("discord_oauth_failed")
      expect(json.fetch("detail")).to include("invalid_grant")
      expect(UserSessionToken.count).to eq(0)
    end

    it "401s with discord_oauth_failed when the code parameter is missing" do
      stub_successful_oauth
      state = begin_oauth

      get "/auth/discord/callback", params: { state: state }

      expect(response).to have_http_status(:unauthorized)
      expect(json.fetch("error")).to eq("discord_oauth_failed")
    end

    it "403s with discord_guild_membership_required for non-members" do
      allow(client).to receive_messages(
        exchange_code!: { "access_token" => "discord-access-token" },
        fetch_user!: discord_user_payload
      )
      allow(client).to receive(:ensure_rpgclub_member!)
        .and_raise(Auth::DiscordOauthClient::GuildMembershipError,
          "Discord user is not a member of TheRPGClub Discord server")
      state = begin_oauth

      get "/auth/discord/callback", params: { code: "good-code", state: state }

      expect(response).to have_http_status(:forbidden)
      expect(json.fetch("error")).to eq("discord_guild_membership_required")
      expect(RpgClubUser.where(user_id: discord_id)).not_to exist
      expect(UserSessionToken.count).to eq(0)
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

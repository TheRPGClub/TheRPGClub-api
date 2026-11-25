# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the authentication layer itself (warden strategies in
# config/initializers/warden.rb), exercised through a representative
# authenticated endpoint.
RSpec.describe "authentication", type: :request do
  describe "GET /api/v1/genres (authenticated endpoint)" do
    it "returns 401 with no Authorization header" do
      get "/api/v1/genres"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end

    it "returns 401 for a garbage bearer token" do
      get "/api/v1/genres", headers: { "Authorization" => "Bearer not-a-real-token" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a non-bearer Authorization header" do
      get "/api/v1/genres", headers: { "Authorization" => "Basic dXNlcjpwYXNz" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for an expired session token" do
      user = create(:user)
      headers = auth_headers_for(user)
      UserSessionToken.where(user_id: user.user_id).update_all(expires_at: 1.hour.ago)

      get "/api/v1/genres", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "authenticates the bot service token" do
      get "/api/v1/genres", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "authenticates a valid user session token" do
      get "/api/v1/genres", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/health" do
    it "is reachable without authentication" do
      get "/api/v1/health"

      expect(response).to have_http_status(:ok)
      expect(json).to eq("ok" => true)
    end
  end

  # Every signed-in request pays for auth, so it stays one query: the member
  # (without the avatar/profile image bytes) joined to their token. Role gates
  # and GET /session reuse that row instead of reading the member again.
  describe "query cost" do
    def user_sqls(headers, path)
      sqls = []
      callback = lambda do |*, payload|
        sql = payload[:sql]
        sqls << sql if sql.match?(/rpg_club_users|user_session_tokens/) && payload[:name] != "SCHEMA"
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path, headers: headers }
      sqls
    end

    it "authenticates in one query that leaves out the image columns" do
      headers = auth_headers_for(create(:user))

      sqls = user_sqls(headers, "/api/v1/genres")

      expect(response).to have_http_status(:ok)
      expect(sqls.size).to eq(1), sqls.join("\n")
      expect(sqls.first).not_to match(/"avatar_blob"|"profile_image"(?!_)|rpg_club_users"?\.\*/)
    end

    it "gates on roles without reading the member again" do
      headers = auth_headers_for(create(:user, role_moderator: true))

      sqls = user_sqls(headers, "/api/v1/live_events")

      expect(response).to have_http_status(:ok)
      expect(sqls.size).to eq(1), sqls.join("\n")
    end

    it "still refuses a member whose role was removed since the token was issued" do
      moderator = create(:user, role_moderator: true)
      headers = auth_headers_for(moderator)
      moderator.update!(role_moderator: false)

      get "/api/v1/live_events", headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end

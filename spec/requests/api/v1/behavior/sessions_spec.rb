# frozen_string_literal: true

require "rails_helper"

# Behavior specs for GET /api/v1/session: the authenticated principal
# (Auth::Principal#as_json) plus, for Discord users, the RPG Club membership
# flags merged with the session token's dev/longstanding flags.
RSpec.describe "api/v1/sessions behavior", type: :request do
  describe "GET /api/v1/session" do
    it "returns the discord_user principal and membership for a user token" do
      user = create(:user, global_name: "Session Tester", discord_avatar: "avatarhash123")

      get "/api/v1/session", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("principal")).to eq(
        "kind" => "discord_user",
        "id" => user.user_id,
        "discord_id" => user.user_id,
        "username" => user.username,
        "global_name" => "Session Tester",
        "avatar" => "avatarhash123",
        "service" => false,
        "dev" => false,
        "longstanding" => false
      )
      expect(json.fetch("principal")).not_to have_key("email")
      expect(json.fetch("membership")).to eq(
        "admin" => false, "moderator" => false, "regular" => false,
        "member" => false, "newcomer" => false, "active" => true,
        "dev" => false, "longstanding" => false
      )
    end

    it "carries the session token's dev and longstanding flags into principal and membership" do
      user = create(:user)

      get "/api/v1/session", headers: auth_headers_for(user, is_dev: true, is_longstanding: true)

      expect(json.fetch("principal")).to include("dev" => true, "longstanding" => true)
      expect(json.fetch("membership")).to include("dev" => true, "longstanding" => true)
    end

    it "reflects role flags and departure in membership" do
      user = create(:user, :admin, role_regular: true, server_left_at: 1.day.ago)

      get "/api/v1/session", headers: auth_headers_for(user)

      expect(json.fetch("membership")).to include(
        "admin" => true, "regular" => true, "active" => false
      )
    end

    it "returns the service principal with a null membership for the bot token" do
      get "/api/v1/session", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("principal")).to include(
        "kind" => "service",
        "id" => "discord_bot",
        "service" => true,
        "dev" => false,
        "longstanding" => false,
        "username" => nil,
        "global_name" => nil
      )
      expect(json.key?("membership")).to be(true)
      expect(json.fetch("membership")).to be_nil
    end

    it "requires authentication" do
      get "/api/v1/session"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end
end

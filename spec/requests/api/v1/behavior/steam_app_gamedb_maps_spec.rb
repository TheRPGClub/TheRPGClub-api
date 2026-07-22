# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Steam app -> GameDB mapping cache endpoints (#166):
# reads are open to any authenticated principal, the upsert write is
# admin-or-service-only, and `historical` returns the distinct game ids a
# user has previously mapped.
RSpec.describe "api/v1/steam_app_gamedb_maps behavior", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/steam_app_gamedb_maps/:steam_app_id" do
    it "returns the mapping looked up by steam_app_id to any authenticated user" do
      map = create(:steam_app_gamedb_map, gamedb_game_id: 555, created_by: user.user_id)

      get "/api/v1/steam_app_gamedb_maps/#{map.steam_app_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "map_id" => map.map_id,
        "steam_app_id" => map.steam_app_id,
        "gamedb_game_id" => 555,
        "status" => "mapped",
        "created_by" => user.user_id
      )
    end

    it "404s for an unknown steam_app_id" do
      get "/api/v1/steam_app_gamedb_maps/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      map = create(:steam_app_gamedb_map)

      get "/api/v1/steam_app_gamedb_maps/#{map.steam_app_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/steam_app_gamedb_maps" do
    let(:steam_app_id) { SecureRandom.random_number(1_000_000_000) }
    let(:payload) do
      { data: { steam_app_id: steam_app_id, gamedb_game_id: 123, status: "mapped", created_by: user.user_id } }
    end

    it "creates a new mapping as the service and returns 201" do
      expect {
        post "/api/v1/steam_app_gamedb_maps", params: payload, headers: service_headers, as: :json
      }.to change(RpgClubSteamAppGamedbMap, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "steam_app_id" => steam_app_id,
        "gamedb_game_id" => 123,
        "status" => "mapped",
        "created_by" => user.user_id
      )
    end

    it "updates the existing mapping keyed on steam_app_id and returns 200" do
      existing = create(:steam_app_gamedb_map, steam_app_id: steam_app_id, gamedb_game_id: 123)

      expect {
        post "/api/v1/steam_app_gamedb_maps",
          params: { data: { steam_app_id: steam_app_id, gamedb_game_id: 456, status: "skipped" } },
          headers: service_headers, as: :json
      }.not_to change(RpgClubSteamAppGamedbMap, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "map_id" => existing.map_id,
        "gamedb_game_id" => 456,
        "status" => "skipped"
      )
      expect(existing.reload).to have_attributes(gamedb_game_id: 456, status: "skipped")
    end

    it "allows an admin user" do
      post "/api/v1/steam_app_gamedb_maps",
        params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/steam_app_gamedb_maps", params: payload, headers: auth_headers_for(user), as: :json
      }.not_to change(RpgClubSteamAppGamedbMap, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "400s when steam_app_id is missing" do
      post "/api/v1/steam_app_gamedb_maps",
        params: { data: { gamedb_game_id: 123, status: "mapped" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "422s on an invalid status" do
      post "/api/v1/steam_app_gamedb_maps",
        params: { data: { steam_app_id: steam_app_id, status: "bogus" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires authentication" do
      post "/api/v1/steam_app_gamedb_maps", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/steam_app_gamedb_maps/historical" do
    it "returns the distinct game ids the user has mapped, excluding skips and other users" do
      create(:steam_app_gamedb_map, created_by: user.user_id, status: "mapped", gamedb_game_id: 101)
      create(:steam_app_gamedb_map, created_by: user.user_id, status: "mapped", gamedb_game_id: 101)
      create(:steam_app_gamedb_map, created_by: user.user_id, status: "mapped", gamedb_game_id: 202)
      create(:steam_app_gamedb_map, created_by: user.user_id, status: "skipped", gamedb_game_id: 303)
      create(:steam_app_gamedb_map, created_by: create(:user).user_id, status: "mapped", gamedb_game_id: 404)

      get "/api/v1/users/#{user.user_id}/steam_app_gamedb_maps/historical",
        headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to match_array([ 101, 202 ])
    end

    it "returns an empty list for a user with no mappings" do
      get "/api/v1/users/#{user.user_id}/steam_app_gamedb_maps/historical", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([])
    end

    it "requires authentication" do
      get "/api/v1/users/#{user.user_id}/steam_app_gamedb_maps/historical"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the server-side Steam import workflow (web-parity #289):
# the user-nested create that fetches the library through Steam::Client, and
# the advance / apply / skip / remap / igdb_candidates workflow routes. The
# Steam and IGDB clients are stubbed at their constructors, so no spec ever
# reaches a real upstream API.
RSpec.describe "api/v1/steam_collection_imports workflow behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:steam) { instance_double(Steam::Client) }
  let!(:steam_platform) { create(:platform, platform_name: "Steam", platform_code: "STEAM#{SecureRandom.hex(3)}") }

  before { allow(Steam::Client).to receive(:new).and_return(steam) }

  def steam_game(app_id, name, playtime: 0)
    {
      app_id: app_id, name: name, playtime_forever_minutes: playtime,
      playtime_windows_minutes: playtime, playtime_mac_minutes: nil, playtime_linux_minutes: nil,
      playtime_deck_minutes: nil, last_played_at: Time.utc(2026, 1, 2, 3, 4, 5)
    }
  end

  describe "POST /api/v1/users/:user_id/steam_collection_imports" do
    let(:steam_id64) { "76561198000000042" }

    before do
      allow(steam).to receive(:resolve_profile).with("example")
        .and_return(steam_id64: steam_id64, identifier_kind: "vanity", raw_identifier: "example",
          profile_path: "profiles/#{steam_id64}")
      allow(steam).to receive(:owned_games).with(steam_id64).and_return(
        steam_id64: steam_id64, profile_name: "Example", game_count: 2,
        games: [ steam_game(10, "Half-Life", playtime: 120), steam_game(20, "Portal") ]
      )
    end

    it "resolves the profile, fetches the library and creates the import with its items" do
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id, "status" => "active", "total_count" => 2, "current_index" => 0,
        "steam_id64" => steam_id64, "steam_profile_ref" => "example",
        "source_profile_name" => "Example", "test_mode" => false
      )
      import = RpgClubSteamCollectionImport.find(json.dig("data", "import_id"))
      items = import.items.order(:row_index)
      expect(items.map { |item| [ item.row_index, item.steam_app_id, item.steam_app_name, item.status ] })
        .to eq([ [ 1, 10, "Half-Life", "pending" ], [ 2, 20, "Portal", "pending" ] ])
      expect(items.first).to have_attributes(playtime_forever_min: 120, playtime_windows_min: 120,
        playtime_mac_min: nil, last_played_at: Time.utc(2026, 1, 2, 3, 4, 5))
    end

    it "persists the session but rolls back the items in test_mode" do
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example", test_mode: true } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("test_mode" => true, "total_count" => 2)
      import = RpgClubSteamCollectionImport.find(json.dig("data", "import_id"))
      expect(import.total_count).to eq(0)
      expect(import.items).to be_empty
    end

    it "maps Steam profile errors to 422 with the error code, creating nothing" do
      allow(steam).to receive(:owned_games)
        .and_raise(Steam::Client::Error.new("private_profile", "No visible games were returned."))

      expect {
        post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
          params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubSteamCollectionImport, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "private_profile", "message" => "No visible games were returned.")
    end

    it "maps an invalid identifier to 422" do
      allow(steam).to receive(:resolve_profile)
        .and_raise(Steam::Client::Error.new("invalid_identifier", "Unsupported Steam profile identifier format."))

      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "bad id!" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to eq("invalid_identifier")
    end

    it "maps upstream failures to 502, rate limiting to 503 and a missing key to 503" do
      { "api_unavailable" => 502, "api_unauthorized" => 502, "api_rate_limited" => 503 }.each do |code, status|
        allow(steam).to receive(:owned_games).and_raise(Steam::Client::Error.new(code, "upstream"))

        post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
          params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(status)
        expect(json.fetch("error")).to eq(code)
      end

      allow(steam).to receive(:resolve_profile).and_raise(Steam::Client::ConfigurationError, "STEAM_WEB_API_KEY must be set")
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json.fetch("error")).to eq("steam_not_configured")
    end

    it "refuses a second open import before calling Steam" do
      create(:steam_collection_import, user: owner, status: "paused")

      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json.fetch("error")).to include("user already has an active or paused import")
      expect(steam).not_to have_received(:resolve_profile)
    end

    it "is forbidden for another member" do
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(steam).not_to have_received(:resolve_profile)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the admin/service-only manual release write
# (POST /api/v1/games/:id/releases, the bot's addReleaseInfo). Reads live on
# GET /api/v1/games/:id/releases, covered in the games behavior spec.
RSpec.describe "api/v1/releases behavior", type: :request do
  let(:game) { create(:game) }
  let(:platform) { create(:platform) }
  let(:region) { create(:region) }
  let(:payload) do
    {
      data: {
        platform_id: platform.platform_id,
        region_id: region.region_id,
        format: "Physical",
        release_date: "2024-05-10",
        notes: "collector edition"
      }
    }
  end

  describe "POST /api/v1/games/:id/releases" do
    it "creates the release with platform/region labels flattened in" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
      }.to change(GamedbRelease.where(game_id: game.game_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "game_id" => game.game_id,
        "platform_id" => platform.platform_id,
        "region_id" => region.region_id,
        "format" => "Physical",
        "notes" => "collector edition",
        "platform_code" => platform.platform_code,
        "platform_name" => platform.platform_name,
        "region_code" => region.region_code,
        "region_name" => region.region_name
      )

      release = GamedbRelease.find(json.dig("data", "release_id"))
      expect(release.release_date).to eq(Time.utc(2024, 5, 10))
    end

    it "bumps the game's updated_at so the cached relations invalidate" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
      }.to change { game.reload.updated_at }
    end

    it "allows duplicates (plain insert, matching the bot)" do
      2.times do
        post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
        expect(response).to have_http_status(:created)
      end

      expect(GamedbRelease.where(game_id: game.game_id).count).to eq(2)
    end

    it "allows an admin user" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "accepts a null format" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: region.region_id } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "format")).to be_nil
      expect(json.dig("data", "release_date")).to be_nil
    end

    it "422s for a format outside Physical/Digital" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: region.region_id, format: "Streaming" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Format")
    end

    it "422s when platform_id is missing" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: { data: { region_id: region.region_id } }, headers: service_headers, as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown region_id" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: 999_999_999 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Region")
    end

    it "404s for an unknown game" do
      post "/api/v1/games/999999999/releases", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { platform_id: platform.platform_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      post "/api/v1/games/#{game.game_id}/releases", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

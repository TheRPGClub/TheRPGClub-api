# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the game-modes taxonomy endpoints (TaxonomyEndpoints
# concern, backed by GamedbGameModeDef): list/search/pagination, show, and the
# admin/service-only upsert-by-IGDB-id.
RSpec.describe "api/v1/modes behavior", type: :request do
  describe "GET /api/v1/modes" do
    it "lists modes ordered by name with pagination meta" do
      create(:mode, name: "ordtest zz split screen")
      create(:mode, name: "ordtest aa co-operative")

      get "/api/v1/modes", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |m| m.fetch("name") }
      expect(names).to eq([ "ordtest aa co-operative", "ordtest zz split screen" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented mode fields" do
      mode = create(:mode)

      get "/api/v1/modes", params: { q: mode.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "mode_id" => mode.mode_id,
        "name" => mode.name,
        "igdb_game_mode_id" => mode.igdb_game_mode_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:mode, name: "Single Player xq1")
      create(:mode, name: "Battle Royale xq2")

      get "/api/v1/modes", params: { q: "single player" }, headers: service_headers

      names = json.fetch("data").map { |m| m.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Battle Royale xq2")
    end

    it "paginates with page/per" do
      create_list(:mode, 3)

      get "/api/v1/modes", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:mode, 3)

      get "/api/v1/modes", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "requires authentication" do
      get "/api/v1/modes"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/modes/:id" do
    it "returns the mode" do
      mode = create(:mode)

      get "/api/v1/modes/#{mode.mode_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("mode_id" => mode.mode_id, "name" => mode.name)
    end

    it "404s for an unknown id" do
      get "/api/v1/modes/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      mode = create(:mode)

      get "/api/v1/modes/#{mode.mode_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/modes" do
    let(:payload) { { data: { name: "Multiplayer", igdb_game_mode_id: 424_242 } } }

    it "creates a new mode as the service and returns 201" do
      expect {
        post "/api/v1/modes", params: payload, headers: service_headers, as: :json
      }.to change(GamedbGameModeDef, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Multiplayer", "igdb_game_mode_id" => 424_242)
    end

    it "returns the existing mode with 200 when the IGDB id is already known, keeping its name" do
      existing = create(:mode, name: "Original Name", igdb_game_mode_id: 424_242)

      expect {
        post "/api/v1/modes", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbGameModeDef, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("mode_id" => existing.mode_id, "name" => "Original Name")
    end

    it "allows an admin user" do
      post "/api/v1/modes", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/modes", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbGameModeDef, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_game_mode_id is missing" do
      post "/api/v1/modes", params: { data: { name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_game_mode_id")
    end

    it "422s when name is blank on create" do
      post "/api/v1/modes", params: { data: { igdb_game_mode_id: 424_243 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/modes", params: { name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/modes", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

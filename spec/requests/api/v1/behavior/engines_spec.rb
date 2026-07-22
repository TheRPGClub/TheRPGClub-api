# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the engines taxonomy endpoints (TaxonomyEndpoints
# concern): list/search/pagination, show, and the admin/service-only
# upsert-by-IGDB-id.
RSpec.describe "api/v1/engines behavior", type: :request do
  describe "GET /api/v1/engines" do
    it "lists engines ordered by name with pagination meta" do
      create(:engine, name: "ordtest zz unreal")
      create(:engine, name: "ordtest aa anvil")

      get "/api/v1/engines", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |e| e.fetch("name") }
      expect(names).to eq([ "ordtest aa anvil", "ordtest zz unreal" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented engine fields" do
      engine = create(:engine)

      get "/api/v1/engines", params: { q: engine.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "engine_id" => engine.engine_id,
        "name" => engine.name,
        "igdb_engine_id" => engine.igdb_engine_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:engine, name: "RE Engine xq1")
      create(:engine, name: "Frostbite xq2")

      get "/api/v1/engines", params: { q: "re engine" }, headers: service_headers

      names = json.fetch("data").map { |e| e.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Frostbite xq2")
    end

    it "paginates with page/per" do
      create_list(:engine, 3)

      get "/api/v1/engines", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:engine, 3)

      get "/api/v1/engines", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "requires authentication" do
      get "/api/v1/engines"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/engines/:id" do
    it "returns the engine" do
      engine = create(:engine)

      get "/api/v1/engines/#{engine.engine_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("engine_id" => engine.engine_id, "name" => engine.name)
    end

    it "404s for an unknown id" do
      get "/api/v1/engines/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      engine = create(:engine)

      get "/api/v1/engines/#{engine.engine_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/engines" do
    let(:payload) { { data: { name: "Godot", igdb_engine_id: 424_242 } } }

    it "creates a new engine as the service and returns 201" do
      expect {
        post "/api/v1/engines", params: payload, headers: service_headers, as: :json
      }.to change(GamedbEngine, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Godot", "igdb_engine_id" => 424_242)
    end

    it "returns the existing engine with 200 when the IGDB id is already known, keeping its name" do
      existing = create(:engine, name: "Original Name", igdb_engine_id: 424_242)

      expect {
        post "/api/v1/engines", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbEngine, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("engine_id" => existing.engine_id, "name" => "Original Name")
    end

    it "allows an admin user" do
      post "/api/v1/engines", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/engines", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbEngine, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_engine_id is missing" do
      post "/api/v1/engines", params: { data: { name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_engine_id")
    end

    it "422s when name is blank on create" do
      post "/api/v1/engines", params: { data: { igdb_engine_id: 424_243 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/engines", params: { name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/engines", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

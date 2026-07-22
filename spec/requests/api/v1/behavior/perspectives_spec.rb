# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the player-perspectives taxonomy endpoints
# (TaxonomyEndpoints concern): list/search/pagination, show, and the
# admin/service-only upsert-by-IGDB-id.
RSpec.describe "api/v1/perspectives behavior", type: :request do
  describe "GET /api/v1/perspectives" do
    it "lists perspectives ordered by name with pagination meta" do
      create(:perspective, name: "ordtest zz top down")
      create(:perspective, name: "ordtest aa first person")

      get "/api/v1/perspectives", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |p| p.fetch("name") }
      expect(names).to eq([ "ordtest aa first person", "ordtest zz top down" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented perspective fields" do
      perspective = create(:perspective)

      get "/api/v1/perspectives", params: { q: perspective.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "perspective_id" => perspective.perspective_id,
        "name" => perspective.name,
        "igdb_perspective_id" => perspective.igdb_perspective_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:perspective, name: "Third Person xq1")
      create(:perspective, name: "Isometric xq2")

      get "/api/v1/perspectives", params: { q: "third person" }, headers: service_headers

      names = json.fetch("data").map { |p| p.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Isometric xq2")
    end

    it "paginates with page/per" do
      create_list(:perspective, 3)

      get "/api/v1/perspectives", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:perspective, 3)

      get "/api/v1/perspectives", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "requires authentication" do
      get "/api/v1/perspectives"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/perspectives/:id" do
    it "returns the perspective" do
      perspective = create(:perspective)

      get "/api/v1/perspectives/#{perspective.perspective_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "perspective_id" => perspective.perspective_id,
        "name" => perspective.name
      )
    end

    it "404s for an unknown id" do
      get "/api/v1/perspectives/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      perspective = create(:perspective)

      get "/api/v1/perspectives/#{perspective.perspective_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/perspectives" do
    let(:payload) { { data: { name: "Virtual Reality", igdb_perspective_id: 424_242 } } }

    it "creates a new perspective as the service and returns 201" do
      expect {
        post "/api/v1/perspectives", params: payload, headers: service_headers, as: :json
      }.to change(GamedbPerspective, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Virtual Reality", "igdb_perspective_id" => 424_242)
    end

    it "returns the existing perspective with 200 when the IGDB id is already known, keeping its name" do
      existing = create(:perspective, name: "Original Name", igdb_perspective_id: 424_242)

      expect {
        post "/api/v1/perspectives", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbPerspective, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("perspective_id" => existing.perspective_id, "name" => "Original Name")
    end

    it "allows an admin user" do
      post "/api/v1/perspectives", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/perspectives", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbPerspective, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_perspective_id is missing" do
      post "/api/v1/perspectives", params: { data: { name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_perspective_id")
    end

    it "422s when name is blank on create" do
      post "/api/v1/perspectives", params: { data: { igdb_perspective_id: 424_243 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/perspectives", params: { name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/perspectives", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

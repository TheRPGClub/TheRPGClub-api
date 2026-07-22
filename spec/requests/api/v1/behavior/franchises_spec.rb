# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the franchises taxonomy endpoints (TaxonomyEndpoints
# concern): list/search/pagination, show, and the admin/service-only
# upsert-by-IGDB-id.
RSpec.describe "api/v1/franchises behavior", type: :request do
  describe "GET /api/v1/franchises" do
    it "lists franchises ordered by name with pagination meta" do
      create(:franchise, name: "ordtest zz zelda")
      create(:franchise, name: "ordtest aa atelier")

      get "/api/v1/franchises", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |f| f.fetch("name") }
      expect(names).to eq([ "ordtest aa atelier", "ordtest zz zelda" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented franchise fields" do
      franchise = create(:franchise)

      get "/api/v1/franchises", params: { q: franchise.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "franchise_id" => franchise.franchise_id,
        "name" => franchise.name,
        "igdb_franchise_id" => franchise.igdb_franchise_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:franchise, name: "Final Fantasy xq1")
      create(:franchise, name: "Dragon Quest xq2")

      get "/api/v1/franchises", params: { q: "final fantasy" }, headers: service_headers

      names = json.fetch("data").map { |f| f.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Dragon Quest xq2")
    end

    it "paginates with page/per" do
      create_list(:franchise, 3)

      get "/api/v1/franchises", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:franchise, 3)

      get "/api/v1/franchises", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "requires authentication" do
      get "/api/v1/franchises"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/franchises/:id" do
    it "returns the franchise" do
      franchise = create(:franchise)

      get "/api/v1/franchises/#{franchise.franchise_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("franchise_id" => franchise.franchise_id, "name" => franchise.name)
    end

    it "404s for an unknown id" do
      get "/api/v1/franchises/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      franchise = create(:franchise)

      get "/api/v1/franchises/#{franchise.franchise_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/franchises" do
    let(:payload) { { data: { name: "Suikoden", igdb_franchise_id: 424_242 } } }

    it "creates a new franchise as the service and returns 201" do
      expect {
        post "/api/v1/franchises", params: payload, headers: service_headers, as: :json
      }.to change(GamedbFranchise, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Suikoden", "igdb_franchise_id" => 424_242)
    end

    it "returns the existing franchise with 200 when the IGDB id is already known, keeping its name" do
      existing = create(:franchise, name: "Original Name", igdb_franchise_id: 424_242)

      expect {
        post "/api/v1/franchises", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbFranchise, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("franchise_id" => existing.franchise_id, "name" => "Original Name")
    end

    it "allows an admin user" do
      post "/api/v1/franchises", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/franchises", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbFranchise, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_franchise_id is missing" do
      post "/api/v1/franchises", params: { data: { name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_franchise_id")
    end

    it "422s when name is blank on create" do
      post "/api/v1/franchises", params: { data: { igdb_franchise_id: 424_243 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/franchises", params: { name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/franchises", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

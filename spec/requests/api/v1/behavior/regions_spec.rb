# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the regions endpoints: the paginated list with its exact
# `code` / `igdb_id` lookups, show, and the admin/service-only
# upsert-by-IGDB-id keyed on `igdb_region_id` (the bot's `ensureRegion`).
RSpec.describe "api/v1/regions behavior", type: :request do
  describe "GET /api/v1/regions" do
    it "lists regions ordered by region_name with pagination meta" do
      zz = create(:region, region_name: "ordtest zz region #{SecureRandom.hex(4)}")
      aa = create(:region, region_name: "ordtest aa region #{SecureRandom.hex(4)}")

      get "/api/v1/regions", params: { per: 500 }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |r| r.fetch("region_name") }
      expect(names.index(aa.region_name)).to be < names.index(zz.region_name)
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "looks up by exact code as a single-element list with the documented fields" do
      region = create(:region, igdb_region_id: SecureRandom.random_number(1_000_000_000))

      get "/api/v1/regions", params: { code: region.region_code }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "region_id" => region.region_id,
        "region_code" => region.region_code,
        "region_name" => region.region_name,
        "igdb_region_id" => region.igdb_region_id
      )
      expect(json.fetch("meta")).to include("count" => 1)
    end

    it "filters by igdb_id" do
      region = create(:region, igdb_region_id: SecureRandom.random_number(1_000_000_000))
      create(:region, igdb_region_id: SecureRandom.random_number(1_000_000_000))

      get "/api/v1/regions", params: { igdb_id: region.igdb_region_id }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include("region_id" => region.region_id)
    end

    it "paginates with page/per" do
      create_list(:region, 3)

      get "/api/v1/regions", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "requires authentication" do
      get "/api/v1/regions"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/regions/:id" do
    it "returns the region" do
      region = create(:region)

      get "/api/v1/regions/#{region.region_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "region_id" => region.region_id,
        "region_code" => region.region_code,
        "region_name" => region.region_name
      )
    end

    it "404s for an unknown id" do
      get "/api/v1/regions/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      region = create(:region)

      get "/api/v1/regions/#{region.region_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/regions" do
    let(:igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:code) { "Q#{SecureRandom.hex(3)}" }
    let(:payload) { { data: { code: code, name: "Questlandia", igdb_id: igdb_id } } }

    it "creates a new region as the service and returns 201, mapping the payload onto the columns" do
      expect {
        post "/api/v1/regions", params: payload, headers: service_headers, as: :json
      }.to change(GamedbRegion, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "region_code" => code,
        "region_name" => "Questlandia",
        "igdb_region_id" => igdb_id
      )
    end

    it "returns the existing region with 200 when the IGDB id is already known, keeping its code and name" do
      existing = create(:region, region_name: "Original Region", igdb_region_id: igdb_id)

      expect {
        post "/api/v1/regions", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbRegion, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "region_id" => existing.region_id,
        "region_code" => existing.region_code,
        "region_name" => "Original Region"
      )
    end

    it "allows an admin user" do
      post "/api/v1/regions", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/regions", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbRegion, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_id is missing" do
      post "/api/v1/regions", params: { data: { code: code, name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_id")
    end

    it "422s when code and name are blank on create" do
      post "/api/v1/regions", params: { data: { igdb_id: igdb_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/regions", params: { code: "XX" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/regions", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

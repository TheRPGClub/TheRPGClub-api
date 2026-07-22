# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the themes taxonomy endpoints (TaxonomyEndpoints
# concern): list/search/pagination, show, and the admin/service-only
# upsert-by-IGDB-id.
RSpec.describe "api/v1/themes behavior", type: :request do
  describe "GET /api/v1/themes" do
    it "lists themes ordered by name with pagination meta" do
      create(:theme, name: "ordtest zz warfare")
      create(:theme, name: "ordtest aa fantasy")

      get "/api/v1/themes", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |t| t.fetch("name") }
      expect(names).to eq([ "ordtest aa fantasy", "ordtest zz warfare" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented theme fields" do
      theme = create(:theme)

      get "/api/v1/themes", params: { q: theme.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "theme_id" => theme.theme_id,
        "name" => theme.name,
        "igdb_theme_id" => theme.igdb_theme_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:theme, name: "Science Fiction xq1")
      create(:theme, name: "Horror xq2")

      get "/api/v1/themes", params: { q: "science fiction" }, headers: service_headers

      names = json.fetch("data").map { |t| t.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Horror xq2")
    end

    it "paginates with page/per" do
      create_list(:theme, 3)

      get "/api/v1/themes", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:theme, 3)

      get "/api/v1/themes", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end

    it "requires authentication" do
      get "/api/v1/themes"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/themes/:id" do
    it "returns the theme" do
      theme = create(:theme)

      get "/api/v1/themes/#{theme.theme_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("theme_id" => theme.theme_id, "name" => theme.name)
    end

    it "404s for an unknown id" do
      get "/api/v1/themes/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      theme = create(:theme)

      get "/api/v1/themes/#{theme.theme_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/themes" do
    let(:payload) { { data: { name: "Post-apocalyptic", igdb_theme_id: 424_242 } } }

    it "creates a new theme as the service and returns 201" do
      expect {
        post "/api/v1/themes", params: payload, headers: service_headers, as: :json
      }.to change(GamedbTheme, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Post-apocalyptic", "igdb_theme_id" => 424_242)
    end

    it "returns the existing theme with 200 when the IGDB id is already known, keeping its name" do
      existing = create(:theme, name: "Original Name", igdb_theme_id: 424_242)

      expect {
        post "/api/v1/themes", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbTheme, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("theme_id" => existing.theme_id, "name" => "Original Name")
    end

    it "allows an admin user" do
      post "/api/v1/themes", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/themes", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbTheme, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_theme_id is missing" do
      post "/api/v1/themes", params: { data: { name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_theme_id")
    end

    it "422s when name is blank on create" do
      post "/api/v1/themes", params: { data: { igdb_theme_id: 424_243 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/themes", params: { name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/themes", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

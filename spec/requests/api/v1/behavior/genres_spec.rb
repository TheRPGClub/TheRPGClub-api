# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the genres taxonomy endpoints (TaxonomyEndpoints concern):
# list/search/pagination, show, and the admin/service-only upsert-by-IGDB-id.
RSpec.describe "api/v1/genres behavior", type: :request do
  describe "GET /api/v1/genres" do
    it "lists genres ordered by name with pagination meta" do
      create(:genre, name: "ordtest zz strategy")
      create(:genre, name: "ordtest aa adventure")

      get "/api/v1/genres", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |g| g.fetch("name") }
      expect(names).to eq([ "ordtest aa adventure", "ordtest zz strategy" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the documented genre fields" do
      genre = create(:genre)

      get "/api/v1/genres", params: { q: genre.name }, headers: service_headers

      expect(json.fetch("data").first).to include(
        "genre_id" => genre.genre_id,
        "name" => genre.name,
        "igdb_genre_id" => genre.igdb_genre_id
      )
    end

    it "filters by q case-insensitively" do
      match = create(:genre, name: "Tactical RPG xq1")
      create(:genre, name: "Shooter xq2")

      get "/api/v1/genres", params: { q: "tactical rpg" }, headers: service_headers

      names = json.fetch("data").map { |g| g.fetch("name") }
      expect(names).to include(match.name)
      expect(names).not_to include("Shooter xq2")
    end

    it "paginates with page/per" do
      create_list(:genre, 3)

      get "/api/v1/genres", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "supports the legacy limit/offset alias" do
      create_list(:genre, 3)

      get "/api/v1/genres", params: { limit: 2, offset: 2 }, headers: service_headers

      expect(json.fetch("data").length).to be <= 2
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2)
    end
  end

  describe "GET /api/v1/genres/:id" do
    it "returns the genre" do
      genre = create(:genre)

      get "/api/v1/genres/#{genre.genre_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("genre_id" => genre.genre_id, "name" => genre.name)
    end

    it "404s for an unknown id" do
      get "/api/v1/genres/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/genres" do
    let(:payload) { { data: { name: "Roguelike", igdb_genre_id: 424_242 } } }

    it "creates a new genre as the service and returns 201" do
      expect {
        post "/api/v1/genres", params: payload, headers: service_headers, as: :json
      }.to change(GamedbGenre, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("name" => "Roguelike", "igdb_genre_id" => 424_242)
    end

    it "returns the existing genre with 200 when the IGDB id is already known, keeping its name" do
      existing = create(:genre, name: "Original Name", igdb_genre_id: 424_242)

      expect {
        post "/api/v1/genres", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbGenre, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("genre_id" => existing.genre_id, "name" => "Original Name")
    end

    it "allows an admin user" do
      post "/api/v1/genres", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/genres", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbGenre, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_genre_id is missing" do
      post "/api/v1/genres", params: { data: { name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_genre_id")
    end

    it "422s when name is blank on create" do
      post "/api/v1/genres", params: { data: { igdb_genre_id: 424_243 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/genres", params: { name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end
end

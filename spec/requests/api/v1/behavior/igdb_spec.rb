# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the admin/service-only IGDB discovery proxy
# (GET /api/v1/igdb/search, #122). The Igdb::Client is stubbed at its
# constructor so no spec ever reaches the real IGDB API.
RSpec.describe "api/v1/igdb behavior", type: :request do
  let(:client) { instance_double(Igdb::Client) }

  before { allow(Igdb::Client).to receive(:new).and_return(client) }

  def candidate(igdb_id, name, extra = {})
    {
      igdb_id: igdb_id, name: name, slug: nil, summary: nil, url: nil,
      total_rating: nil, first_release_date: nil, cover_url: nil
    }.merge(extra)
  end

  describe "GET /api/v1/igdb/search" do
    it "searches a single title and tags candidates with already_imported" do
      imported_id = SecureRandom.random_number(1_000_000_000)
      fresh_id = SecureRandom.random_number(1_000_000_000)
      create(:game, igdb_id: imported_id)
      allow(client).to receive(:search).with("zeldaq", limit: 25)
        .and_return([ candidate(imported_id, "Zelda Q"), candidate(fresh_id, "Zelda Q II") ])

      get "/api/v1/igdb/search", params: { q: "zeldaq" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        {
          "igdb_id" => imported_id, "name" => "Zelda Q", "slug" => nil, "summary" => nil,
          "url" => nil, "total_rating" => nil, "first_release_date" => nil, "cover_url" => nil,
          "already_imported" => true
        },
        {
          "igdb_id" => fresh_id, "name" => "Zelda Q II", "slug" => nil, "summary" => nil,
          "url" => nil, "total_rating" => nil, "first_release_date" => nil, "cover_url" => nil,
          "already_imported" => false
        }
      ])
    end

    it "forwards per as the search limit" do
      allow(client).to receive(:search).with("limited", limit: 5).and_return([])

      get "/api/v1/igdb/search", params: { q: "limited", per: 5 }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:search).with("limited", limit: 5)
    end

    it "fans several titles out through one multiquery, keeping matched_query" do
      allow(client).to receive(:multi_search).with([ "zeldaq", "marioq" ], limit: 25).and_return([
        candidate(1, "Zelda Q", matched_query: "zeldaq"),
        candidate(2, "Mario Q", matched_query: "marioq")
      ])

      get "/api/v1/igdb/search", params: { q: [ "zeldaq", "marioq" ] }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |c| c.fetch("matched_query") }).to eq([ "zeldaq", "marioq" ])
      expect(json.fetch("data").first).to include("igdb_id" => 1, "already_imported" => false)
    end

    it "422s for more than 10 titles at once" do
      terms = (1..11).map { |i| "title #{i}" }

      get "/api/v1/igdb/search", params: { q: terms }, headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("too_many_queries")
    end

    it "looks igdb_id values up directly, defaulting the limit to the id count" do
      allow(client).to receive(:search_by_ids).with([ 1, 2, 3 ], limit: 3)
        .and_return([ candidate(1, "One"), candidate(2, "Two"), candidate(3, "Three") ])

      get "/api/v1/igdb/search", params: { igdb_id: "1,2,3" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |c| c.fetch("igdb_id") }).to eq([ 1, 2, 3 ])
    end

    it "drops non-integer igdb_id tokens" do
      allow(client).to receive(:search_by_ids).with([ 5 ], limit: 1).and_return([ candidate(5, "Five") ])

      get "/api/v1/igdb/search", params: { igdb_id: "5,abc" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:search_by_ids).with([ 5 ], limit: 1)
    end

    it "returns an empty list for a blank query" do
      allow(client).to receive(:search).with(nil, limit: 25).and_return([])

      get "/api/v1/igdb/search", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([])
    end

    it "422s when IGDB is not configured" do
      allow(client).to receive(:search).and_raise(Igdb::Client::ConfigurationError, "IGDB_CLIENT_ID must be set")

      get "/api/v1/igdb/search", params: { q: "zeldaq" }, headers: service_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("igdb_not_configured")
    end

    it "502s when the IGDB request fails" do
      allow(client).to receive(:search).and_raise(Igdb::Client::RequestError, "IGDB games request failed")

      get "/api/v1/igdb/search", params: { q: "zeldaq" }, headers: service_headers

      expect(response).to have_http_status(:bad_gateway)
      expect(json.fetch("error")).to eq("igdb_request_failed")
    end

    it "allows an admin user" do
      allow(client).to receive(:search).with("adminq", limit: 25).and_return([])

      get "/api/v1/igdb/search", params: { q: "adminq" }, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
    end

    it "forbids a regular user" do
      get "/api/v1/igdb/search", params: { q: "zeldaq" }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      get "/api/v1/igdb/search", params: { q: "zeldaq" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the platforms endpoints: the paginated list with its
# `q` / exact-`code` / IGDB-id filters (trimmed PlatformResource shape), the
# full-record show, and the admin/service-only upsert-by-IGDB-id keyed on
# `igdb_platform_id` (the bot's `ensurePlatform`).
RSpec.describe "api/v1/platforms behavior", type: :request do
  describe "GET /api/v1/platforms" do
    it "lists platforms ordered by platform_name with pagination meta" do
      create(:platform, platform_name: "ordtest zz console")
      create(:platform, platform_name: "ordtest aa handheld")

      get "/api/v1/platforms", params: { q: "ordtest" }, headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |p| p.fetch("platform_name") }
      expect(names).to eq([ "ordtest aa handheld", "ordtest zz console" ])
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "serializes the audited platform fields and trims the IGDB bookkeeping columns" do
      platform = create(:platform, platform_abbreviation: "ABBR1", igdb_platform_id: SecureRandom.random_number(1_000_000_000))

      get "/api/v1/platforms", params: { q: platform.platform_name }, headers: service_headers

      row = json.fetch("data").first
      expect(row).to include(
        "platform_id" => platform.platform_id,
        "platform_code" => platform.platform_code,
        "platform_name" => platform.platform_name,
        "platform_abbreviation" => "ABBR1",
        "igdb_platform_id" => platform.igdb_platform_id
      )
      expect(row).not_to have_key("platform_slug")
      expect(row).not_to have_key("platform_checksum")
    end

    it "matches q against the platform code too, case-insensitively" do
      match = create(:platform, platform_code: "XQCODE#{SecureRandom.hex(3)}".upcase)
      create(:platform)

      get "/api/v1/platforms", params: { q: match.platform_code.downcase }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include("platform_id" => match.platform_id)
    end

    it "looks up by exact code as a single-element list" do
      platform = create(:platform)
      create(:platform)

      get "/api/v1/platforms", params: { code: platform.platform_code }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include("platform_code" => platform.platform_code)
      expect(json.fetch("meta")).to include("count" => 1)
    end

    it "bulk-resolves igdb_ids[] and the single igdb_id form" do
      a = create(:platform, igdb_platform_id: SecureRandom.random_number(1_000_000_000))
      b = create(:platform, igdb_platform_id: SecureRandom.random_number(1_000_000_000))
      create(:platform, igdb_platform_id: SecureRandom.random_number(1_000_000_000))

      get "/api/v1/platforms", params: { igdb_ids: [ a.igdb_platform_id, b.igdb_platform_id ] },
        headers: service_headers

      ids = json.fetch("data").map { |p| p.fetch("platform_id") }
      expect(ids).to match_array([ a.platform_id, b.platform_id ])

      get "/api/v1/platforms", params: { igdb_id: a.igdb_platform_id }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include("platform_id" => a.platform_id)
    end

    it "paginates with page/per" do
      create_list(:platform, 3)

      get "/api/v1/platforms", params: { per: 2, page: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(2)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "requires authentication" do
      get "/api/v1/platforms"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "GET /api/v1/platforms/:id" do
    it "returns the full record including the IGDB bookkeeping columns" do
      platform = create(:platform, platform_slug: "slug-#{SecureRandom.hex(4)}")

      get "/api/v1/platforms/#{platform.platform_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "platform_id" => platform.platform_id,
        "platform_code" => platform.platform_code,
        "platform_name" => platform.platform_name,
        "platform_slug" => platform.platform_slug
      )
      expect(json.fetch("data")).to have_key("platform_checksum")
    end

    it "404s for an unknown id" do
      get "/api/v1/platforms/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      platform = create(:platform)

      get "/api/v1/platforms/#{platform.platform_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/platforms" do
    let(:igdb_id) { SecureRandom.random_number(1_000_000_000) }
    let(:code) { "NP#{SecureRandom.hex(3)}".upcase }
    let(:payload) { { data: { code: code, name: "New Platform", igdb_id: igdb_id } } }

    it "creates a new platform as the service and returns 201, mapping the payload onto the columns" do
      expect {
        post "/api/v1/platforms", params: payload, headers: service_headers, as: :json
      }.to change(GamedbPlatform, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "platform_code" => code,
        "platform_name" => "New Platform",
        "igdb_platform_id" => igdb_id
      )
    end

    it "returns the existing platform with 200 when the IGDB id is already known, keeping its code and name" do
      existing = create(:platform, platform_name: "Original Platform", igdb_platform_id: igdb_id)

      expect {
        post "/api/v1/platforms", params: payload, headers: service_headers, as: :json
      }.not_to change(GamedbPlatform, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "platform_id" => existing.platform_id,
        "platform_code" => existing.platform_code,
        "platform_name" => "Original Platform"
      )
    end

    it "allows an admin user" do
      post "/api/v1/platforms", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/platforms", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbPlatform, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when igdb_id is missing" do
      post "/api/v1/platforms", params: { data: { code: code, name: "No Id" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("igdb_id")
    end

    it "422s when code and name are blank on create" do
      post "/api/v1/platforms", params: { data: { igdb_id: igdb_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/platforms", params: { code: "XX" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/platforms", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

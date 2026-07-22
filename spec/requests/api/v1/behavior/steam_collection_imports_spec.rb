# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Steam collection import job endpoints (#166): unlike
# the CSV/Completionator sessions, create is not user-nested (the owner
# user_id travels in the body) and items are bulk-inserted via a separate
# member route (see steam_collection_import_items_spec.rb). Covers the
# owner gate, the active-import resume lookup, show/update, and the
# test_mode dry-run rollback (see TestModeRollback).
RSpec.describe "api/v1/steam_collection_imports behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "POST /api/v1/steam_collection_imports" do
    let(:payload) do
      { data: {
        user_id: owner.user_id,
        steam_id64: "76561198000000001",
        steam_profile_ref: "https://steamcommunity.com/id/example",
        source_profile_name: "example",
        test_mode: false
      } }
    end

    it "creates the import job for the owner" do
      expect {
        post "/api/v1/steam_collection_imports",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(RpgClubSteamCollectionImport, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "status" => "active",
        "current_index" => 0,
        "total_count" => 0,
        "steam_id64" => "76561198000000001",
        "steam_profile_ref" => "https://steamcommunity.com/id/example",
        "source_profile_name" => "example",
        "test_mode" => false
      )
      expect(RpgClubSteamCollectionImport.find(json.dig("data", "import_id")).user_id).to eq(owner.user_id)
    end

    it "always persists the session row in test_mode so it can be referenced across requests" do
      post "/api/v1/steam_collection_imports",
        params: payload.deep_merge(data: { test_mode: true }),
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "test_mode")).to be(true)

      import = RpgClubSteamCollectionImport.find(json.dig("data", "import_id"))
      expect(import.test_mode).to be(true)
    end

    it "defaults test_mode to false when omitted" do
      pending "possible bug: omitting test_mode inserts NULL (PG::NotNullViolation -> 500) " \
              "instead of applying the documented false default"

      post "/api/v1/steam_collection_imports",
        params: { data: { user_id: owner.user_id, steam_id64: "76561198000000002" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "test_mode")).to be(false)
    end

    it "allows the service to create on behalf of the user" do
      post "/api/v1/steam_collection_imports", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user_id")).to eq(owner.user_id)
    end

    it "forbids a user creating an import for someone else" do
      expect {
        post "/api/v1/steam_collection_imports",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(RpgClubSteamCollectionImport, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when steam_id64 is missing" do
      post "/api/v1/steam_collection_imports",
        params: { data: { user_id: owner.user_id } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Steam id64")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/steam_collection_imports",
        params: { user_id: owner.user_id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/steam_collection_imports", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/steam_collection_imports/active" do
    it "returns the most recent active or paused import" do
      create(:steam_collection_import, user: owner, status: "completed")
      create(:steam_collection_import, user: owner, status: "active", created_at: 2.hours.ago)
      newest = create(:steam_collection_import, user: owner, status: "paused")

      get "/api/v1/users/#{owner.user_id}/steam_collection_imports/active", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("import_id" => newest.import_id, "status" => "paused")
    end

    it "404s when the user has no active or paused import" do
      create(:steam_collection_import, user: owner, status: "canceled")

      get "/api/v1/users/#{owner.user_id}/steam_collection_imports/active", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "forbids another user" do
      create(:steam_collection_import, user: owner)

      get "/api/v1/users/#{owner.user_id}/steam_collection_imports/active", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/steam_collection_imports/active"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/steam_collection_imports/:id" do
    it "shows the import to its owner" do
      import = create(:steam_collection_import, user: owner, source_profile_name: "gaben", total_count: 5)

      get "/api/v1/steam_collection_imports/#{import.import_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "import_id" => import.import_id,
        "user_id" => owner.user_id,
        "steam_id64" => import.steam_id64,
        "source_profile_name" => "gaben",
        "total_count" => 5
      )
    end

    it "allows the service" do
      import = create(:steam_collection_import, user: owner)

      get "/api/v1/steam_collection_imports/#{import.import_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "forbids another user" do
      import = create(:steam_collection_import, user: owner)

      get "/api/v1/steam_collection_imports/#{import.import_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id as the service" do
      get "/api/v1/steam_collection_imports/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      import = create(:steam_collection_import, user: owner)

      get "/api/v1/steam_collection_imports/#{import.import_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/steam_collection_imports/:id" do
    it "updates status and current_index for the owner" do
      import = create(:steam_collection_import, user: owner)

      patch "/api/v1/steam_collection_imports/#{import.import_id}",
        params: { data: { status: "paused", current_index: 13 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "paused", "current_index" => 13)
      expect(import.reload).to have_attributes(status: "paused", current_index: 13)
    end

    it "responds with the update but rolls it back for a test_mode import" do
      import = create(:steam_collection_import, user: owner, test_mode: true)

      patch "/api/v1/steam_collection_imports/#{import.import_id}",
        params: { data: { status: "completed", current_index: 4 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "completed", "current_index" => 4)
      expect(import.reload).to have_attributes(status: "active", current_index: 0)
    end

    it "422s on an invalid status" do
      import = create(:steam_collection_import, user: owner)

      patch "/api/v1/steam_collection_imports/#{import.import_id}",
        params: { data: { status: "bogus" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(import.reload.status).to eq("active")
    end

    it "forbids another user" do
      import = create(:steam_collection_import, user: owner)

      patch "/api/v1/steam_collection_imports/#{import.import_id}",
        params: { data: { status: "canceled" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(import.reload.status).to eq("active")
    end

    it "404s for an unknown id as the service" do
      patch "/api/v1/steam_collection_imports/999999999",
        params: { data: { status: "paused" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      import = create(:steam_collection_import, user: owner)

      patch "/api/v1/steam_collection_imports/#{import.import_id}",
        params: { data: { status: "paused" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the per-app Steam collection import item endpoints
# (#166): the bulk insert that also bumps the parent's total_count, the
# next_pending poll, the by-status/by-reason counts, item show, and the
# outcome update — including the test_mode rollback where the response
# reflects the write but nothing survives to the next request.
RSpec.describe "api/v1/steam_collection_import_items behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:import) { create(:steam_collection_import, user: owner) }

  describe "POST /api/v1/steam_collection_imports/:id/items" do
    let(:payload) do
      { data: { items: [
        { steam_app_id: 400, steam_app_name: "Portal", playtime_forever_min: 600,
          playtime_windows_min: 500, playtime_deck_min: 100, last_played_at: "2024-04-01T12:30:00Z" },
        { steam_app_id: 620, steam_app_name: "Portal 2" }
      ] } }
    end

    it "bulk-inserts pending items and bumps total_count for the owner" do
      expect {
        post "/api/v1/steam_collection_imports/#{import.import_id}/items",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(RpgClubSteamCollectionImportItem.where(import_id: import.import_id), :count).by(2)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("import_id" => import.import_id, "total_count" => 2)
      expect(import.reload.total_count).to eq(2)

      items = import.items.order(:row_index)
      expect(items.map(&:row_index)).to eq([ 0, 1 ])
      expect(items.map(&:status).uniq).to eq([ "pending" ])
      expect(items.first).to have_attributes(
        steam_app_id: 400, steam_app_name: "Portal", playtime_forever_min: 600,
        playtime_windows_min: 500, playtime_deck_min: 100
      )
      expect(items.first.last_played_at).to be_present
    end

    it "appends to total_count and honors an explicit row_index" do
      existing = create(:steam_collection_import, user: owner, total_count: 1)
      create(:steam_collection_import_item, import: existing, row_index: 0)

      post "/api/v1/steam_collection_imports/#{existing.import_id}/items",
        params: { data: { items: [ { steam_app_id: 70, steam_app_name: "Half-Life", row_index: 1 } ] } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "total_count")).to eq(2)
      expect(existing.reload.total_count).to eq(2)
      expect(existing.items.order(:row_index).map(&:row_index)).to eq([ 0, 1 ])
    end

    it "responds as if the insert succeeded but rolls everything back for a test_mode import" do
      test_import = create(:steam_collection_import, user: owner, test_mode: true)

      post "/api/v1/steam_collection_imports/#{test_import.import_id}/items",
        params: payload, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("import_id" => test_import.import_id, "total_count" => 2)

      expect(test_import.reload.total_count).to eq(0)
      expect(test_import.items.count).to eq(0)

      get "/api/v1/steam_collection_imports/#{test_import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to be_nil
    end

    it "allows the service" do
      post "/api/v1/steam_collection_imports/#{import.import_id}/items",
        params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/steam_collection_imports/#{import.import_id}/items",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(RpgClubSteamCollectionImportItem, :count)

      expect(response).to have_http_status(:forbidden)
    end

    # insert_all (non-bang) emits ON CONFLICT DO NOTHING, so a row_index
    # collision with an existing item is silently dropped rather than
    # rejected — while total_count is still bumped by the batch size.
    it "silently skips item rows whose row_index collides with an existing item" do
      existing_item = create(:steam_collection_import_item, import: import, row_index: 0,
        steam_app_name: "Existing App")

      post "/api/v1/steam_collection_imports/#{import.import_id}/items",
        params: { data: { items: [ { steam_app_id: 10, steam_app_name: "Counter-Strike" } ] } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(import.items.count).to eq(1)
      expect(existing_item.reload.steam_app_name).to eq("Existing App")
      expect(import.reload.total_count).to eq(1)
    end

    it "404s for an unknown import id as the service" do
      post "/api/v1/steam_collection_imports/999999999/items",
        params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/steam_collection_imports/#{import.import_id}/items", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/steam_collection_imports/:id/items/next_pending" do
    it "returns the lowest-row_index pending item and advances as apps finish" do
      create(:steam_collection_import_item, import: import, row_index: 0, status: "added")
      second = create(:steam_collection_import_item, import: import, row_index: 2)
      first = create(:steam_collection_import_item, import: import, row_index: 1)

      get "/api/v1/steam_collection_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "item_id" => first.item_id, "row_index" => 1, "status" => "pending", "import_id" => import.import_id
      )

      first.update!(status: "skipped", result_reason: "manual_skip")
      get "/api/v1/steam_collection_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(json.fetch("data")).to include("item_id" => second.item_id, "row_index" => 2)
    end

    it "returns data: null once every app has been processed" do
      create(:steam_collection_import_item, import: import, row_index: 0, status: "added")

      get "/api/v1/steam_collection_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to have_key("data")
      expect(json.fetch("data")).to be_nil
    end

    it "forbids another user" do
      get "/api/v1/steam_collection_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown import id as the service" do
      get "/api/v1/steam_collection_imports/999999999/items/next_pending", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/steam_collection_imports/#{import.import_id}/items/next_pending"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/steam_collection_imports/:id/items/counts" do
    it "counts items by status and by result_reason" do
      create(:steam_collection_import_item, import: import, row_index: 0, status: "added",
        result_reason: "auto_match")
      create(:steam_collection_import_item, import: import, row_index: 1, status: "added",
        result_reason: "auto_match")
      create(:steam_collection_import_item, import: import, row_index: 2, status: "skipped",
        result_reason: "manual_skip")

      get "/api/v1/steam_collection_imports/#{import.import_id}/items/counts", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "import_id")).to eq(import.import_id)
      expect(json.dig("data", "by_status")).to eq("added" => 2, "skipped" => 1)
      expect(json.dig("data", "by_result_reason")).to eq("auto_match" => 2, "manual_skip" => 1)
    end

    it "forbids another user" do
      get "/api/v1/steam_collection_imports/#{import.import_id}/items/counts",
        headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/steam_collection_imports/#{import.import_id}/items/counts"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/steam_collection_import_items/:id" do
    it "shows the item's raw and resolved fields to the owner" do
      item = create(:steam_collection_import_item, import: import, row_index: 3,
        steam_app_id: 1091500, steam_app_name: "Cyberpunk 2077", playtime_forever_min: 1200)

      get "/api/v1/steam_collection_import_items/#{item.item_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "item_id" => item.item_id,
        "import_id" => import.import_id,
        "row_index" => 3,
        "steam_app_id" => 1091500,
        "steam_app_name" => "Cyberpunk 2077",
        "playtime_forever_min" => 1200,
        "status" => "pending"
      )
    end

    it "forbids another user" do
      item = create(:steam_collection_import_item, import: import)

      get "/api/v1/steam_collection_import_items/#{item.item_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id as the service" do
      get "/api/v1/steam_collection_import_items/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      item = create(:steam_collection_import_item, import: import)

      get "/api/v1/steam_collection_import_items/#{item.item_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/steam_collection_import_items/:id" do
    it "records the app outcome for the owner" do
      game = create(:game)
      item = create(:steam_collection_import_item, import: import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { status: "added", match_confidence: "fuzzy", gamedb_game_id: game.game_id,
                          collection_entry_id: 88, result_reason: "auto_match",
                          match_candidate_json: '{"title":"match"}' } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "status" => "added",
        "match_confidence" => "fuzzy",
        "gamedb_game_id" => game.game_id,
        "collection_entry_id" => 88,
        "result_reason" => "auto_match",
        "match_candidate_json" => '{"title":"match"}'
      )
      expect(item.reload).to have_attributes(
        status: "added", match_confidence: "fuzzy", gamedb_game_id: game.game_id, result_reason: "auto_match"
      )
    end

    it "allows the service" do
      item = create(:steam_collection_import_item, import: import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { status: "failed", result_reason: "add_failed", error_text: "boom" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(item.reload).to have_attributes(status: "failed", result_reason: "add_failed", error_text: "boom")
    end

    it "responds with the update but rolls it back when the import is in test_mode" do
      test_import = create(:steam_collection_import, user: owner, test_mode: true)
      item = create(:steam_collection_import_item, import: test_import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { status: "added", gamedb_game_id: 777 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "added", "gamedb_game_id" => 777)
      expect(item.reload).to have_attributes(status: "pending", gamedb_game_id: nil)
    end

    it "422s on an invalid status" do
      item = create(:steam_collection_import_item, import: import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { status: "bogus" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(item.reload.status).to eq("pending")
    end

    it "422s on an invalid match_confidence" do
      item = create(:steam_collection_import_item, import: import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { match_confidence: "psychic" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(item.reload.match_confidence).to be_nil
    end

    it "forbids another user" do
      item = create(:steam_collection_import_item, import: import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { status: "added" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(item.reload.status).to eq("pending")
    end

    it "404s for an unknown id as the service" do
      patch "/api/v1/steam_collection_import_items/999999999",
        params: { data: { status: "added" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      item = create(:steam_collection_import_item, import: import)

      patch "/api/v1/steam_collection_import_items/#{item.item_id}",
        params: { data: { status: "added" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the per-row Completionator import item endpoints (#164):
# the next_pending poll the bot works through, item show, and the outcome
# update — including the test_mode rollback inherited from the parent import.
RSpec.describe "api/v1/completionator_import_items behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:import) { create(:completionator_import, user: owner) }

  describe "GET /api/v1/completionator_imports/:id/items/next_pending" do
    it "returns the lowest-row_index pending item and advances as rows finish" do
      create(:completionator_import_item, import: import, row_index: 0, status: "updated")
      second = create(:completionator_import_item, import: import, row_index: 2)
      first = create(:completionator_import_item, import: import, row_index: 1)

      get "/api/v1/completionator_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "item_id" => first.item_id, "row_index" => 1, "status" => "pending", "import_id" => import.import_id
      )

      first.update!(status: "added")
      get "/api/v1/completionator_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(json.fetch("data")).to include("item_id" => second.item_id, "row_index" => 2)
    end

    it "returns data: null once every row has been processed" do
      create(:completionator_import_item, import: import, row_index: 0, status: "skipped")

      get "/api/v1/completionator_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to have_key("data")
      expect(json.fetch("data")).to be_nil
    end

    it "allows the service" do
      create(:completionator_import_item, import: import, row_index: 0)

      get "/api/v1/completionator_imports/#{import.import_id}/items/next_pending", headers: service_headers

      expect(response).to have_http_status(:ok)
    end

    it "forbids another user" do
      get "/api/v1/completionator_imports/#{import.import_id}/items/next_pending",
        headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown import id as the service" do
      get "/api/v1/completionator_imports/999999999/items/next_pending", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/completionator_imports/#{import.import_id}/items/next_pending"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/completionator_import_items/:id" do
    it "shows the item's raw and resolved fields to the owner" do
      item = create(:completionator_import_item, import: import, row_index: 6,
        game_title: "Xenogears", platform_name: "PlayStation", completion_type: "Finished")

      get "/api/v1/completionator_import_items/#{item.item_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "item_id" => item.item_id,
        "import_id" => import.import_id,
        "row_index" => 6,
        "game_title" => "Xenogears",
        "platform_name" => "PlayStation",
        "completion_type" => "Finished",
        "status" => "pending"
      )
    end

    it "forbids another user" do
      item = create(:completionator_import_item, import: import)

      get "/api/v1/completionator_import_items/#{item.item_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown id as the service" do
      get "/api/v1/completionator_import_items/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      item = create(:completionator_import_item, import: import)

      get "/api/v1/completionator_import_items/#{item.item_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/completionator_import_items/:id" do
    it "records the row outcome for the owner" do
      game = create(:game)
      item = create(:completionator_import_item, import: import)

      patch "/api/v1/completionator_import_items/#{item.item_id}",
        params: { data: { status: "added", gamedb_game_id: game.game_id, completion_id: 512 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "status" => "added",
        "gamedb_game_id" => game.game_id,
        "completion_id" => 512
      )
      expect(item.reload).to have_attributes(
        status: "added", gamedb_game_id: game.game_id, completion_id: 512
      )
    end

    it "allows the service" do
      item = create(:completionator_import_item, import: import)

      patch "/api/v1/completionator_import_items/#{item.item_id}",
        params: { data: { status: "failed", error_text: "no candidate" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(item.reload).to have_attributes(status: "failed", error_text: "no candidate")
    end

    it "responds with the update but rolls it back when the import is in test_mode" do
      test_import = create(:completionator_import, user: owner, test_mode: true)
      item = create(:completionator_import_item, import: test_import)

      patch "/api/v1/completionator_import_items/#{item.item_id}",
        params: { data: { status: "added", completion_id: 99 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "added", "completion_id" => 99)
      expect(item.reload).to have_attributes(status: "pending", completion_id: nil)
    end

    it "422s on an invalid status" do
      item = create(:completionator_import_item, import: import)

      patch "/api/v1/completionator_import_items/#{item.item_id}",
        params: { data: { status: "bogus" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(item.reload.status).to eq("pending")
    end

    it "forbids another user" do
      item = create(:completionator_import_item, import: import)

      patch "/api/v1/completionator_import_items/#{item.item_id}",
        params: { data: { status: "added" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(item.reload.status).to eq("pending")
    end

    it "404s for an unknown id as the service" do
      patch "/api/v1/completionator_import_items/999999999",
        params: { data: { status: "added" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      item = create(:completionator_import_item, import: import)

      patch "/api/v1/completionator_import_items/#{item.item_id}",
        params: { data: { status: "added" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

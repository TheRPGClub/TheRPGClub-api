# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the user game-collection endpoints: the user-scoped list
# with the bot's search filters, the per-platform summary, the game-scoped
# community-ownership list, and the detail CRUD. Reads and writes are open to
# any authenticated principal — collection writes are documented as NOT
# owner-restricted (tracked by the controller-hardening companion issue).
RSpec.describe "api/v1/collections behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/collections" do
    it "lists only that user's entries with the joined platform fields" do
      platform = create(:platform)
      entry = create(:collection_entry, user: owner, platform: platform, note: "boxed")
      create(:collection_entry, user: other_user)

      get "/api/v1/users/#{owner.user_id}/collections", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "entry_id" => entry.entry_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => entry.gamedb_game_id,
        "platform_id" => platform.platform_id,
        "platform_name" => platform.platform_name,
        "ownership_type" => "Digital",
        "note" => "boxed"
      )
      expect(json.fetch("meta")).to include("count" => 1)
    end

    it "filters by game title via q" do
      game = create(:game, title: "colq chrono #{SecureRandom.hex(4)}")
      match = create(:collection_entry, user: owner, game: game)
      create(:collection_entry, user: owner)

      get "/api/v1/users/#{owner.user_id}/collections", params: { q: "colq chrono" },
        headers: auth_headers_for(owner)

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include("entry_id" => match.entry_id)
    end

    it "filters by platform name substring" do
      platform = create(:platform, platform_name: "colplat deck #{SecureRandom.hex(4)}")
      match = create(:collection_entry, user: owner, platform: platform)
      create(:collection_entry, user: owner)

      get "/api/v1/users/#{owner.user_id}/collections", params: { platform: "colplat deck" },
        headers: auth_headers_for(owner)

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include("entry_id" => match.entry_id)
    end

    it "filters by exact ownership_type and by game_id" do
      physical = create(:collection_entry, user: owner, ownership_type: "Physical")
      digital = create(:collection_entry, user: owner, ownership_type: "Digital")

      get "/api/v1/users/#{owner.user_id}/collections", params: { ownership_type: "Physical" },
        headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ physical.entry_id ])

      get "/api/v1/users/#{owner.user_id}/collections", params: { game_id: digital.gamedb_game_id },
        headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ digital.entry_id ])
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/collections"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/collections" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, ownership_type: "Physical", note: "day one" } } }

    it "creates an entry scoped to the path user and returns the full record" do
      expect {
        post "/api/v1/users/#{owner.user_id}/collections",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameCollection.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "ownership_type" => "Physical",
        "note" => "day one",
        "is_shared" => true
      )
      expect(json.fetch("data")).to have_key("created_at")
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/collections", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user_id")).to eq(owner.user_id)
    end

    it "is documented as not owner-restricted: another user may write, scoped to the path user" do
      post "/api/v1/users/#{owner.user_id}/collections",
        params: payload, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user_id")).to eq(owner.user_id)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/collections",
        params: { data: { gamedb_game_id: 999_999_999, ownership_type: "Digital" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when gamedb_game_id is missing" do
      post "/api/v1/users/#{owner.user_id}/collections",
        params: { data: { ownership_type: "Digital" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/collections",
        params: { gamedb_game_id: game.game_id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/collections", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/collections/platform_summary" do
    it "returns the total plus per-platform tallies, null-platform entries collapsed into one row" do
      plat_a = create(:platform, platform_name: "aaa summary plat #{SecureRandom.hex(4)}")
      plat_b = create(:platform, platform_name: "bbb summary plat #{SecureRandom.hex(4)}")
      create_list(:collection_entry, 2, user: owner, platform: plat_a)
      create(:collection_entry, user: owner, platform: plat_b)
      create(:collection_entry, user: owner, platform: nil)
      create(:collection_entry, user: other_user, platform: plat_a)

      get "/api/v1/users/#{owner.user_id}/collections/platform_summary", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "total_count")).to eq(4)

      counts = json.dig("data", "platform_counts")
      expect(counts.length).to eq(3)
      expect(counts[0]).to include(
        "platform_id" => plat_a.platform_id,
        "platform_name" => plat_a.platform_name,
        "count" => 2
      )
      expect(counts[1]).to include("platform_id" => plat_b.platform_id, "count" => 1)
      expect(counts[2]).to include("platform_id" => nil, "platform_name" => nil, "count" => 1)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/collections/platform_summary"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id/collections" do
    it "lists every member's entry for the game with the embedded user" do
      game = create(:game)
      entry = create(:collection_entry, user: owner, game: game)
      create(:collection_entry, user: other_user)

      get "/api/v1/games/#{game.game_id}/collections", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "entry_id" => entry.entry_id,
        "gamedb_game_id" => game.game_id
      )
      expect(json.dig("data", 0, "user")).to include(
        "user_id" => owner.user_id,
        "username" => owner.username
      )
    end

    it "requires authentication" do
      game = create(:game)

      get "/api/v1/games/#{game.game_id}/collections"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/collections/:id" do
    it "returns the full record with is_shared, timestamps and the joined platform fields" do
      platform = create(:platform)
      entry = create(:collection_entry, user: owner, platform: platform, note: "collector's edition")

      get "/api/v1/collections/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "entry_id" => entry.entry_id,
        "user_id" => owner.user_id,
        "note" => "collector's edition",
        "is_shared" => true,
        "platform_name" => platform.platform_name,
        "platform_abbreviation" => platform.platform_abbreviation
      )
      expect(json.fetch("data")).to have_key("created_at")
      expect(json.fetch("data")).to have_key("updated_at")
    end

    it "404s for an unknown id" do
      get "/api/v1/collections/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      entry = create(:collection_entry, user: owner)

      get "/api/v1/collections/#{entry.entry_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/collections/:id" do
    it "partially updates the entry" do
      entry = create(:collection_entry, user: owner)

      patch "/api/v1/collections/#{entry.entry_id}",
        params: { data: { note: "now physical", ownership_type: "Physical" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "note")).to eq("now physical")
      expect(json.dig("data", "ownership_type")).to eq("Physical")
      expect(entry.reload.ownership_type).to eq("Physical")
    end

    it "is documented as not owner-restricted: another user may update" do
      entry = create(:collection_entry, user: owner)

      patch "/api/v1/collections/#{entry.entry_id}",
        params: { data: { note: "edited by someone else" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.note).to eq("edited by someone else")
    end

    it "supports PUT as an alias for the partial update" do
      entry = create(:collection_entry, user: owner)

      put "/api/v1/collections/#{entry.entry_id}",
        params: { data: { note: "via put" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.note).to eq("via put")
    end

    it "422s for an unknown platform_id" do
      entry = create(:collection_entry, user: owner)

      patch "/api/v1/collections/#{entry.entry_id}",
        params: { data: { platform_id: 999_999_999 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for an unknown id" do
      patch "/api/v1/collections/999999999",
        params: { data: { note: "nope" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      entry = create(:collection_entry, user: owner)

      patch "/api/v1/collections/#{entry.entry_id}", params: { data: { note: "x" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/collections/:id" do
    it "deletes the entry" do
      entry = create(:collection_entry, user: owner)

      delete "/api/v1/collections/#{entry.entry_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameCollection.exists?(entry.entry_id)).to be(false)
    end

    it "404s for an unknown id" do
      delete "/api/v1/collections/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      entry = create(:collection_entry, user: owner)

      delete "/api/v1/collections/#{entry.entry_id}"

      expect(response).to have_http_status(:unauthorized)
      expect(UserGameCollection.exists?(entry.entry_id)).to be(true)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the server-side collection CSV import workflow (#290):
# `advance` walks pending rows (auto-resolving id-carrying rows and single
# exact title matches) until one needs a human, and the item endpoints
# apply / skip / remap / igdb_candidates resolve that row. Owner-only.
RSpec.describe "api/v1/collection_csv_import workflow behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:import) { create(:collection_csv_import, user: owner) }
  let(:token) { SecureRandom.hex(4) }

  def item(row_index, **attrs)
    create(:collection_csv_import_item, import: import, row_index: row_index, **attrs)
  end

  def advance(as: owner)
    post "/api/v1/collection_csv_imports/#{import.import_id}/advance", headers: auth_headers_for(as), as: :json
  end

  def collection_entries
    UserGameCollection.where(user_id: owner.user_id)
  end

  describe "POST /api/v1/collection_csv_imports/:id/advance" do
    it "auto-applies a gamedb_id row with the row's platform, ownership and note, then completes" do
      platform = create(:platform, platform_name: "Advance Deck #{token}")
      game = create(:game)
      row = item(2, raw_title: "whatever", raw_gamedb_id: game.game_id, raw_platform: platform.platform_name,
        raw_ownership_type: "physical", raw_note: "signed")

      advance

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.fetch("item")).to be_nil
      expect(data.dig("import", "status")).to eq("completed")
      expect(data.dig("counts", "by_status")).to eq("added" => 1)
      entry = collection_entries.sole
      expect(entry).to have_attributes(gamedb_game_id: game.game_id, platform_id: platform.platform_id,
        ownership_type: "Physical", note: "signed")
      expect(row.reload).to have_attributes(status: "added", result_reason: "csv_gamedb_id", match_confidence: "manual",
        gamedb_game_id: game.game_id, collection_entry_id: entry.entry_id, platform_id: platform.platform_id)
    end

    it "fails a gamedb_id row whose game does not exist" do
      row = item(2, raw_gamedb_id: 999_999_999)

      advance

      expect(row.reload).to have_attributes(status: "failed", result_reason: "invalid_row",
        error_text: "GameDB id 999999999 was not found.")
      expect(collection_entries).to be_empty
    end

    it "imports an igdb_id row through IGDB and applies it" do
      game = create(:game, igdb_id: SecureRandom.random_number(1_000_000_000))
      row = item(2, raw_igdb_id: game.igdb_id)

      advance

      expect(row.reload).to have_attributes(status: "added", result_reason: "csv_igdb_id", gamedb_game_id: game.game_id)
    end

    it "fails an igdb_id row IGDB does not know" do
      importer = instance_double(Gamedb::IgdbGameImporter)
      allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer)
      allow(importer).to receive(:import!).and_raise(Gamedb::IgdbGameImporter::MissingIgdbGameError)
      row = item(2, raw_igdb_id: 123_456_789)

      advance

      expect(row.reload).to have_attributes(status: "failed", result_reason: "invalid_row")
      expect(row.error_text).to include("123456789")
    end

    it "auto-applies a single exact title candidate" do
      game = create(:game, title: "Advance Exact #{token}")
      row = item(2, raw_title: "Advance Exact #{token}")

      advance

      expect(row.reload).to have_attributes(status: "added", result_reason: "auto_match", match_confidence: "exact",
        gamedb_game_id: game.game_id)
    end

    it "stops at the first row that needs a human and returns its candidates" do
      create(:game, title: "Advance Exact #{token}")
      first = create(:game, title: "Advance Fuzzy #{token} One")
      second = create(:game, title: "Advance Fuzzy #{token} Two")
      item(2, raw_title: "Advance Exact #{token}")
      review = item(3, raw_title: "Advance Fuzzy #{token}")
      item(4, raw_title: "Untouched #{token}")

      advance

      data = json.fetch("data")
      expect(data.dig("item", "item_id")).to eq(review.item_id)
      expect(data.fetch("candidates").map { |candidate| candidate.fetch("game_id") })
        .to contain_exactly(first.game_id, second.game_id)
      expect(data.fetch("candidates").first).to include("title", "cover_url")
      expect(data.fetch("match_confidence")).to eq("fuzzy")
      expect(data.dig("import", "status")).to eq("active")
      expect(data.dig("import", "current_index")).to eq(3)
      expect(data.dig("counts", "by_status")).to eq("added" => 1, "pending" => 2)
      expect(review.reload.match_candidate_json).to be_present

      advance
      expect(json.dig("data", "item", "item_id")).to eq(review.item_id)
    end

    it "returns a row with no candidates for review" do
      review = item(2, raw_title: "Nothing Matches Here #{token}")

      advance

      expect(json.dig("data", "item", "item_id")).to eq(review.item_id)
      expect(json.dig("data", "candidates")).to eq([])
      expect(json.dig("data", "match_confidence")).to be_nil
    end

    it "applies without a platform and flags a platform the resolver can't map" do
      game = create(:game)
      row = item(2, raw_gamedb_id: game.game_id, raw_platform: "Nowhere Console #{token}")

      advance

      expect(row.reload).to have_attributes(status: "added", result_reason: "platform_unresolved", platform_id: nil,
        error_text: "Platform not recognized; imported without platform.")
      expect(collection_entries.sole.platform_id).to be_nil
    end

    it "skips a row whose game is already in the collection" do
      game = create(:game)
      UserGameCollection.create!(user_id: owner.user_id, gamedb_game_id: game.game_id, ownership_type: "Digital")
      row = item(2, raw_gamedb_id: game.game_id)

      advance

      expect(row.reload).to have_attributes(status: "skipped", result_reason: "duplicate", gamedb_game_id: game.game_id)
      expect(collection_entries.count).to eq(1)
    end

    it "stops after the per-request auto-apply cap and leaves the import active" do
      stub_const("Imports::CollectionCsvWorkflow::MAX_AUTO_APPLIES", 2)
      games = create_list(:game, 3)
      games.each_with_index { |game, index| item(index + 2, raw_gamedb_id: game.game_id) }

      advance

      expect(json.dig("data", "item")).to be_nil
      expect(json.dig("data", "import", "status")).to eq("active")
      expect(json.dig("data", "counts", "by_status")).to eq("added" => 2, "pending" => 1)

      advance
      expect(json.dig("data", "import", "status")).to eq("completed")
    end

    it "409s when the import is not active" do
      import.update!(status: "paused")

      advance

      expect(response).to have_http_status(:conflict)
      expect(json).to eq("error" => "import_not_active")
    end

    it "rolls every write back for a test_mode import" do
      import.update!(test_mode: true)
      game = create(:game)
      row = item(2, raw_gamedb_id: game.game_id)

      advance

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "import", "status")).to eq("completed")
      expect(row.reload.status).to eq("pending")
      expect(import.reload.status).to eq("active")
      expect(collection_entries).to be_empty
    end

    it "forbids another user" do
      item(2, raw_gamedb_id: create(:game).game_id)

      advance(as: other_user)

      expect(response).to have_http_status(:forbidden)
      expect(collection_entries).to be_empty
    end
  end

  describe "POST /api/v1/collection_csv_import_items/:id/apply" do
    def apply_item(row, data, as: owner)
      post "/api/v1/collection_csv_import_items/#{row.item_id}/apply", params: { data: data },
        headers: auth_headers_for(as), as: :json
    end

    it "applies a chosen GameDB game with the row's platform, ownership and note" do
      platform = create(:platform, platform_name: "Apply Deck #{token}")
      game = create(:game)
      row = item(2, raw_title: "Choose me", raw_platform: platform.platform_name, raw_ownership_type: "other",
        raw_note: "lent out")

      apply_item(row, { game_id: game.game_id })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("item_id" => row.item_id, "status" => "added",
        "result_reason" => "manual_remap", "match_confidence" => "manual", "gamedb_game_id" => game.game_id)
      expect(collection_entries.sole).to have_attributes(gamedb_game_id: game.game_id,
        platform_id: platform.platform_id, ownership_type: "Other", note: "lent out")
    end

    it "imports an IGDB pick, stores it as the only candidate, and applies it" do
      game = create(:game, title: "Igdb Pick #{token}")
      importer = instance_double(Gamedb::IgdbGameImporter)
      allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer)
      allow(importer).to receive(:import!).with(4242)
        .and_return(Gamedb::IgdbGameImporter::Result.new(game: game, created: true, images: []))
      row = item(2)

      apply_item(row, { igdb_id: 4242 })

      expect(response).to have_http_status(:ok)
      expect(row.reload).to have_attributes(status: "added", result_reason: "manual_remap", gamedb_game_id: game.game_id)
      expect(Imports::CandidateFinder.load(row.match_candidate_json).map(&:game_id)).to eq([ game.game_id ])
    end

    it "marks a duplicate collection entry as skipped" do
      game = create(:game)
      UserGameCollection.create!(user_id: owner.user_id, gamedb_game_id: game.game_id, ownership_type: "Digital")
      row = item(2)

      apply_item(row, { game_id: game.game_id })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "skipped", "result_reason" => "duplicate")
    end

    it "404s for an unknown game and maps IGDB failures to HTTP statuses" do
      row = item(2)
      importer = instance_double(Gamedb::IgdbGameImporter)
      allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer)
      allow(importer).to receive(:import!).and_raise(Gamedb::IgdbGameImporter::MissingIgdbGameError)

      apply_item(row, { game_id: 999_999_999 })
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "game_not_found")

      apply_item(row, { igdb_id: 77 })
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "igdb_game_not_found")

      apply_item(row, { igdb_id: "abc" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "invalid_igdb_id")

      expect(row.reload.status).to eq("pending")
    end

    it "422s unless exactly one of game_id or igdb_id is given" do
      row = item(2)

      apply_item(row, { title: "x" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "game_id_or_igdb_id_required")

      apply_item(row, { game_id: 1, igdb_id: 2 })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "409s for an item that is no longer pending, or an import that is not active" do
      game = create(:game)
      done = item(2, status: "added")
      apply_item(done, { game_id: game.game_id })
      expect(response).to have_http_status(:conflict)
      expect(json).to eq("error" => "item_not_pending")

      import.update!(status: "paused")
      apply_item(item(3), { game_id: game.game_id })
      expect(response).to have_http_status(:conflict)
      expect(json).to eq("error" => "import_not_active")
    end

    it "forbids another user" do
      row = item(2)

      apply_item(row, { game_id: create(:game).game_id }, as: other_user)

      expect(response).to have_http_status(:forbidden)
      expect(collection_entries).to be_empty
    end
  end

  describe "POST /api/v1/collection_csv_import_items/:id/skip" do
    it "skips the row" do
      row = item(2)

      post "/api/v1/collection_csv_import_items/#{row.item_id}/skip", headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "skipped", "result_reason" => "manual_skip")
      expect(row.reload.status).to eq("skipped")
    end

    it "forbids another user" do
      row = item(2)

      post "/api/v1/collection_csv_import_items/#{row.item_id}/skip", headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(row.reload.status).to eq("pending")
    end
  end

  describe "POST /api/v1/collection_csv_import_items/:id/remap" do
    def remap(row, title, as: owner)
      post "/api/v1/collection_csv_import_items/#{row.item_id}/remap", params: { data: { title: title } },
        headers: auth_headers_for(as), as: :json
    end

    it "re-searches GameDB and returns the review payload" do
      game = create(:game, title: "Remapped Title #{token}")
      row = item(2, raw_title: "Something Else #{token}")

      remap(row, "Remapped Title #{token}")

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.dig("item", "item_id")).to eq(row.item_id)
      expect(data.fetch("candidates").map { |candidate| candidate.fetch("game_id") }).to eq([ game.game_id ])
      expect(data.fetch("match_confidence")).to eq("exact")
      expect(row.reload).to have_attributes(status: "pending", result_reason: nil, match_confidence: "exact")
    end

    it "records no_candidate when nothing matches" do
      row = item(2)

      remap(row, "Nothing At All #{token}")

      expect(json.dig("data", "candidates")).to eq([])
      expect(row.reload.result_reason).to eq("no_candidate")
    end

    it "422s on a blank title" do
      remap(item(2), "  ")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "title_required")
    end

    it "forbids another user" do
      remap(item(2), "Anything", as: other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/collection_csv_import_items/:id/igdb_candidates" do
    let(:client) { instance_double(Igdb::Client) }

    before { allow(Igdb::Client).to receive(:new).and_return(client) }

    def hit(igdb_id, name)
      { igdb_id: igdb_id, name: name, slug: nil, summary: nil, url: nil, total_rating: nil,
        first_release_date: nil, cover_url: nil }
    end

    it "searches IGDB by progressive title variants of the row title, flagging already imported games" do
      imported = create(:game, igdb_id: SecureRandom.random_number(1_000_000_000))
      row = item(2, raw_title: "The Game: Deluxe")
      allow(client).to receive(:search).with("The Game: Deluxe", limit: 10).and_return([])
      allow(client).to receive(:search).with("The Game Deluxe", limit: 10)
        .and_return([ hit(imported.igdb_id, "The Game Deluxe"), hit(1, "Other") ])

      get "/api/v1/collection_csv_import_items/#{row.item_id}/igdb_candidates", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |candidate| [ candidate["igdb_id"], candidate["already_imported"] ] })
        .to eq([ [ imported.igdb_id, true ], [ 1, false ] ])
    end

    it "searches `q` instead of the row title when given" do
      row = item(2, raw_title: "Ignored")
      allow(client).to receive(:search).with("Custom", limit: 10).and_return([ hit(5, "Custom") ])

      get "/api/v1/collection_csv_import_items/#{row.item_id}/igdb_candidates", params: { q: "Custom" },
        headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |candidate| candidate["igdb_id"] }).to eq([ 5 ])
    end

    it "maps IGDB errors" do
      row = item(2, raw_title: "Boom")
      allow(client).to receive(:search).and_raise(Igdb::Client::RequestError, "down")

      get "/api/v1/collection_csv_import_items/#{row.item_id}/igdb_candidates", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.fetch("error")).to eq("igdb_request_failed")
    end

    it "forbids another user" do
      get "/api/v1/collection_csv_import_items/#{item(2).item_id}/igdb_candidates",
        headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

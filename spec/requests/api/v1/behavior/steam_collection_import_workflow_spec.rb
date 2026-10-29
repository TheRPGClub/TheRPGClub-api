# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the server-side Steam import workflow (web-parity #289):
# the user-nested create that fetches the library through Steam::Client, and
# the advance / apply / skip / remap / igdb_candidates workflow routes. The
# Steam and IGDB clients are stubbed at their constructors, so no spec ever
# reaches a real upstream API.
RSpec.describe "api/v1/steam_collection_imports workflow behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:steam) { instance_double(Steam::Client) }
  let!(:steam_platform) { create(:platform, platform_name: "Steam", platform_code: "STEAM#{SecureRandom.hex(3)}") }

  before { allow(Steam::Client).to receive(:new).and_return(steam) }

  def steam_game(app_id, name, playtime: 0)
    {
      app_id: app_id, name: name, playtime_forever_minutes: playtime,
      playtime_windows_minutes: playtime, playtime_mac_minutes: nil, playtime_linux_minutes: nil,
      playtime_deck_minutes: nil, last_played_at: Time.utc(2026, 1, 2, 3, 4, 5)
    }
  end

  describe "POST /api/v1/users/:user_id/steam_collection_imports" do
    let(:steam_id64) { "76561198000000042" }

    before do
      allow(steam).to receive(:resolve_profile).with("example")
        .and_return(steam_id64: steam_id64, identifier_kind: "vanity", raw_identifier: "example",
          profile_path: "profiles/#{steam_id64}")
      allow(steam).to receive(:owned_games).with(steam_id64).and_return(
        steam_id64: steam_id64, profile_name: "Example", game_count: 2,
        games: [ steam_game(10, "Half-Life", playtime: 120), steam_game(20, "Portal") ]
      )
    end

    it "resolves the profile, fetches the library and creates the import with its items" do
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id, "status" => "active", "total_count" => 2, "current_index" => 0,
        "steam_id64" => steam_id64, "steam_profile_ref" => "example",
        "source_profile_name" => "Example", "test_mode" => false
      )
      import = RpgClubSteamCollectionImport.find(json.dig("data", "import_id"))
      items = import.items.order(:row_index)
      expect(items.map { |item| [ item.row_index, item.steam_app_id, item.steam_app_name, item.status ] })
        .to eq([ [ 1, 10, "Half-Life", "pending" ], [ 2, 20, "Portal", "pending" ] ])
      expect(items.first).to have_attributes(playtime_forever_min: 120, playtime_windows_min: 120,
        playtime_mac_min: nil, last_played_at: Time.utc(2026, 1, 2, 3, 4, 5))
    end

    it "persists the session with its total_count but rolls back the items in test_mode, like the CSV create" do
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example", test_mode: true } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("test_mode" => true, "total_count" => 2)
      import = RpgClubSteamCollectionImport.find(json.dig("data", "import_id"))
      expect(import.total_count).to eq(2)
      expect(import.items).to be_empty
    end

    it "maps Steam profile errors to 422 with the error code, creating nothing" do
      allow(steam).to receive(:owned_games)
        .and_raise(Steam::Client::Error.new("private_profile", "No visible games were returned."))

      expect {
        post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
          params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubSteamCollectionImport, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "private_profile", "message" => "No visible games were returned.")
    end

    it "maps an invalid identifier to 422" do
      allow(steam).to receive(:resolve_profile)
        .and_raise(Steam::Client::Error.new("invalid_identifier", "Unsupported Steam profile identifier format."))

      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "bad id!" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_identifier")
    end

    it "maps upstream failures to 502, rate limiting to 503 and a missing key to 503" do
      { "api_unavailable" => 502, "api_unauthorized" => 502, "api_rate_limited" => 503 }.each do |code, status|
        allow(steam).to receive(:owned_games).and_raise(Steam::Client::Error.new(code, "upstream"))

        post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
          params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(status)
        expect(json.fetch("error")).to eq(code)
      end

      allow(steam).to receive(:resolve_profile).and_raise(Steam::Client::ConfigurationError, "STEAM_WEB_API_KEY must be set")
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json.fetch("error")).to eq("steam_not_configured")
    end

    it "refuses a second open import before calling Steam" do
      create(:steam_collection_import, user: owner, status: "paused")

      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("user already has an active or paused import")
      expect(steam).not_to have_received(:resolve_profile)
    end

    it "is forbidden for another member" do
      post "/api/v1/users/#{owner.user_id}/steam_collection_imports",
        params: { data: { steam_profile: "example" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(steam).not_to have_received(:resolve_profile)
    end
  end

  describe "POST /api/v1/steam_collection_imports/:id/advance" do
    let(:import) { create(:steam_collection_import, user: owner) }

    def advance(as: owner)
      post "/api/v1/steam_collection_imports/#{import.import_id}/advance", headers: auth_headers_for(as), as: :json
    end

    it "auto-applies a single exact match, then stops at the first item that needs a human" do
      exact = create(:game, title: "Hollow Knightz")
      fuzzy_a = create(:game, title: "Ori Blindz Forest")
      fuzzy_b = create(:game, title: "Ori Blindz Forest Definitive")
      auto = create(:steam_collection_import_item, import: import, row_index: 1,
        steam_app_id: 367_520, steam_app_name: "Hollow Knightz®")
      review = create(:steam_collection_import_item, import: import, row_index: 2, steam_app_name: "Ori Blindz")

      advance

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.dig("import", "status")).to eq("active")
      expect(data.dig("import", "current_index")).to eq(2)
      expect(data.dig("item", "item_id")).to eq(review.item_id)
      # The two GameDB hits, then the historical boost (the game just auto-mapped).
      expect(data.fetch("candidates").map { |c| c.fetch("game_id") })
        .to eq([ fuzzy_a.game_id, fuzzy_b.game_id, exact.game_id ])
      expect(data.fetch("candidates").first.keys).to contain_exactly("game_id", "title", "cover_url")
      expect(data.fetch("match_confidence")).to eq("fuzzy")
      expect(data.dig("counts", "by_status")).to eq("added" => 1, "pending" => 1)

      expect(auto.reload).to have_attributes(status: "added", result_reason: "auto_match", gamedb_game_id: exact.game_id)
      entry = UserGameCollection.find(auto.collection_entry_id)
      expect(entry).to have_attributes(user_id: owner.user_id, gamedb_game_id: exact.game_id,
        platform_id: steam_platform.platform_id, ownership_type: "Digital")
      expect(RpgClubSteamAppGamedbMap.find_by(steam_app_id: 367_520))
        .to have_attributes(status: "mapped", gamedb_game_id: exact.game_id, created_by: owner.user_id)
      expect(review.reload).to have_attributes(status: "pending", match_confidence: "fuzzy")
      expect(Imports::CandidateFinder.load(review.match_candidate_json).map(&:game_id))
        .to eq([ fuzzy_a.game_id, fuzzy_b.game_id, exact.game_id ])
    end

    it "marks the import completed once no pending items remain" do
      game = create(:game, title: "Celestez")
      create(:steam_collection_import_item, import: import, steam_app_name: "Celestez")

      advance

      data = json.fetch("data")
      expect(data.fetch("item")).to be_nil
      expect(data.fetch("candidates")).to eq([])
      expect(data.dig("import", "status")).to eq("completed")
      expect(import.reload.status).to eq("completed")
      expect(UserGameCollection.where(user_id: owner.user_id, gamedb_game_id: game.game_id)).to exist
    end

    it "caps auto-applies per request, leaving the import active for the next call" do
      stub_const("Imports::SteamWorkflow::MAX_AUTO_APPLIES", 2)
      3.times do |index|
        title = "Capped Gamez #{index} #{SecureRandom.hex(2)}"
        create(:game, title: title)
        create(:steam_collection_import_item, import: import, row_index: index + 1, steam_app_name: title)
      end

      advance

      data = json.fetch("data")
      expect(data.dig("counts", "by_status")).to eq("added" => 2, "pending" => 1)
      expect(data.fetch("item")).to be_nil
      expect(data.dig("import", "status")).to eq("active")
      expect(import.items.where(status: "pending").count).to eq(1)

      advance

      expect(json.dig("data", "counts", "by_status")).to eq("added" => 3)
      expect(json.dig("data", "import", "status")).to eq("completed")
    end

    it "uses the Steam app map: a mapped app's game becomes the single candidate" do
      mapped = create(:game, title: "Some Other Titlez")
      create(:game, title: "Steam Namez")
      create(:steam_app_gamedb_map, steam_app_id: 4242, gamedb_game_id: mapped.game_id, status: "mapped")
      item = create(:steam_collection_import_item, import: import, steam_app_id: 4242, steam_app_name: "Steam Namez")

      advance

      data = json.fetch("data")
      expect(data.dig("item", "item_id")).to eq(item.item_id)
      expect(data.fetch("candidates").map { |c| c.fetch("game_id") }).to eq([ mapped.game_id ])
    end

    it "flags an app the map says to skip as skip_mapped without searching" do
      create(:game, title: "Skippedz Tool")
      create(:steam_app_gamedb_map, steam_app_id: 777, gamedb_game_id: nil, status: "skipped")
      item = create(:steam_collection_import_item, import: import, steam_app_id: 777, steam_app_name: "Skippedz Tool")

      advance

      data = json.fetch("data")
      expect(data.dig("item", "item_id")).to eq(item.item_id)
      expect(data.dig("item", "result_reason")).to eq("skip_mapped")
      expect(data.fetch("candidates")).to eq([])
      expect(data.fetch("match_confidence")).to be_nil
    end

    it "adds the member's historically mapped games when there are several candidates" do
      create(:game, title: "Boostz One")
      create(:game, title: "Boostz Two")
      historical = create(:game, title: "Unrelated Historicz")
      create(:steam_app_gamedb_map, gamedb_game_id: historical.game_id, status: "mapped", created_by: owner.user_id)
      create(:steam_collection_import_item, import: import, steam_app_name: "Boostz")

      advance

      expect(json.dig("data", "candidates").map { |c| c.fetch("title") })
        .to eq([ "Boostz One", "Boostz Two", "Unrelated Historicz" ])
    end

    it "rolls the auto-applies back for a test_mode import" do
      test_import = create(:steam_collection_import, user: owner, test_mode: true)
      create(:game, title: "Dryrunz")
      item = create(:steam_collection_import_item, import: test_import, steam_app_name: "Dryrunz")

      post "/api/v1/steam_collection_imports/#{test_import.import_id}/advance", headers: auth_headers_for(owner), as: :json

      expect(json.dig("data", "counts", "by_status")).to eq("added" => 1)
      expect(json.dig("data", "import", "status")).to eq("completed")
      expect(item.reload.status).to eq("pending")
      expect(test_import.reload.status).to eq("active")
      expect(UserGameCollection.where(user_id: owner.user_id)).not_to exist
    end

    it "409s unless the import is active" do
      import.update!(status: "paused")

      advance

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("import_not_active")
    end

    it "is forbidden for another member" do
      create(:steam_collection_import_item, import: import)

      advance(as: other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Steam import item actions" do
    let(:import) { create(:steam_collection_import, user: owner) }
    let(:item) { create(:steam_collection_import_item, import: import, steam_app_id: 1234, steam_app_name: "Hadez") }
    let(:importer) { instance_double(Gamedb::IgdbGameImporter) }

    before { allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer) }

    def item_post(action, data = nil, as: owner)
      post "/api/v1/steam_collection_import_items/#{item.item_id}/#{action}",
        params: data ? { data: data } : {}, headers: auth_headers_for(as), as: :json
    end

    describe "POST .../:id/apply" do
      it "adds a chosen GameDB game to the collection (Digital, Steam) and maps the app" do
        game = create(:game, title: "Hades Game")

        item_post("apply", { game_id: game.game_id })

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("item_id" => item.item_id, "status" => "added",
          "result_reason" => "manual_remap", "match_confidence" => "manual", "gamedb_game_id" => game.game_id)
        entry = UserGameCollection.find(json.dig("data", "collection_entry_id"))
        expect(entry).to have_attributes(user_id: owner.user_id, gamedb_game_id: game.game_id,
          platform_id: steam_platform.platform_id, ownership_type: "Digital")
        expect(RpgClubSteamAppGamedbMap.find_by(steam_app_id: 1234))
          .to have_attributes(status: "mapped", gamedb_game_id: game.game_id, created_by: owner.user_id)
      end

      it "imports an IGDB game first when given igdb_id" do
        igdb_id = SecureRandom.random_number(1_000_000_000)
        allow(importer).to receive(:import!).with(igdb_id) do
          Gamedb::IgdbGameImporter::Result.new(game: create(:game, title: "Hades IGDB", igdb_id: igdb_id),
            created: true, images: [])
        end

        item_post("apply", { igdb_id: igdb_id })

        expect(response).to have_http_status(:ok)
        game = GamedbGame.find_by!(igdb_id: igdb_id)
        expect(json.fetch("data")).to include("status" => "added", "gamedb_game_id" => game.game_id)
      end

      it "reuses a game already in GameDB for that igdb_id without calling IGDB" do
        game = create(:game, igdb_id: SecureRandom.random_number(1_000_000_000))
        allow(importer).to receive(:import!)

        item_post("apply", { igdb_id: game.igdb_id })

        expect(json.fetch("data")).to include("status" => "added", "gamedb_game_id" => game.game_id)
        expect(importer).not_to have_received(:import!)
      end

      it "records a duplicate collection entry as skipped/duplicate and still maps the app" do
        game = create(:game)
        create(:collection_entry, user: owner, game: game, platform_id: steam_platform.platform_id)

        item_post("apply", { game_id: game.game_id })

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("status" => "skipped", "result_reason" => "duplicate")
        expect(RpgClubSteamAppGamedbMap.find_by(steam_app_id: 1234).status).to eq("mapped")
      end

      it "maps IGDB failures to 404 / 502 and an unknown game_id to 404" do
        allow(importer).to receive(:import!).and_raise(Gamedb::IgdbGameImporter::MissingIgdbGameError)
        item_post("apply", { igdb_id: 99_999_999 })
        expect(response).to have_http_status(:not_found)
        expect(json.fetch("error")).to eq("igdb_game_not_found")

        allow(importer).to receive(:import!).and_raise(Igdb::Client::RequestError)
        item_post("apply", { igdb_id: 99_999_998 })
        expect(response).to have_http_status(:bad_gateway)
        expect(json.fetch("error")).to eq("igdb_request_failed")

        item_post("apply", { game_id: 0 })
        expect(response).to have_http_status(:not_found)
        expect(json.fetch("error")).to eq("game_not_found")
        expect(item.reload.status).to eq("pending")
      end

      it "422s unless exactly one of game_id and igdb_id is given" do
        item_post("apply", { note: "nothing" })
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("game_id_or_igdb_id_required")

        item_post("apply", { game_id: 1, igdb_id: 2 })
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("game_id_or_igdb_id_required")
      end

      it "409s for an item that is no longer pending" do
        item.update!(status: "skipped")

        item_post("apply", { game_id: create(:game).game_id })

        expect(response).to have_http_status(:conflict)
        expect(json.fetch("error")).to eq("item_not_pending")
      end

      it "rolls the apply back for a test_mode import" do
        test_item = create(:steam_collection_import_item, import: create(:steam_collection_import, user: owner, test_mode: true))

        post "/api/v1/steam_collection_import_items/#{test_item.item_id}/apply",
          params: { data: { game_id: create(:game).game_id } }, headers: auth_headers_for(owner), as: :json

        expect(json.dig("data", "status")).to eq("added")
        expect(test_item.reload.status).to eq("pending")
        expect(UserGameCollection.where(user_id: owner.user_id)).not_to exist
      end

      it "is forbidden for another member" do
        item_post("apply", { game_id: create(:game).game_id }, as: other_user)

        expect(response).to have_http_status(:forbidden)
        expect(item.reload.status).to eq("pending")
      end
    end

    describe "POST .../:id/skip" do
      it "marks the item skipped and records the app as skipped in the map" do
        item_post("skip")

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("status" => "skipped", "result_reason" => "manual_skip")
        expect(RpgClubSteamAppGamedbMap.find_by(steam_app_id: 1234))
          .to have_attributes(status: "skipped", gamedb_game_id: nil, created_by: owner.user_id)
      end

      it "is forbidden for another member" do
        item_post("skip", as: other_user)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "POST .../:id/remap" do
      it "re-searches GameDB for the title and persists the candidates" do
        hit = create(:game, title: "Remapped Titlez")

        item_post("remap", { title: "Remapped Titlez" })

        expect(response).to have_http_status(:ok)
        data = json.fetch("data")
        expect(data.dig("item", "item_id")).to eq(item.item_id)
        expect(data.fetch("candidates").map { |c| c.fetch("game_id") }).to eq([ hit.game_id ])
        expect(data.fetch("match_confidence")).to eq("exact")
        expect(Imports::CandidateFinder.load(item.reload.match_candidate_json).map(&:game_id)).to eq([ hit.game_id ])
        expect(item.status).to eq("pending")
      end

      it "records no_candidate when nothing matches" do
        item_post("remap", { title: "Nothing Matches This Zzqx" })

        expect(json.dig("data", "candidates")).to eq([])
        expect(item.reload).to have_attributes(result_reason: "no_candidate", match_candidate_json: nil)
      end

      it "422s for a blank title" do
        item_post("remap", { title: "  " })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("title_required")
      end

      it "is forbidden for another member" do
        item_post("remap", { title: "x" }, as: other_user)

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET .../:id/igdb_candidates" do
      let(:igdb) { instance_double(Igdb::Client) }

      before { allow(Igdb::Client).to receive(:new).and_return(igdb) }

      def igdb_result(igdb_id, name)
        { igdb_id: igdb_id, name: name, slug: nil, summary: nil, url: nil, total_rating: nil,
          first_release_date: nil, cover_url: nil }
      end

      it "searches IGDB by progressive variants of the Steam name, flagging already imported games" do
        imported = create(:game, igdb_id: SecureRandom.random_number(1_000_000_000))
        item.update!(steam_app_name: "Hadez™ (2020)")
        allow(igdb).to receive(:search).and_return([])
        allow(igdb).to receive(:search).with("Hadez™", limit: 10)
          .and_return([ igdb_result(imported.igdb_id, "Hadez"), igdb_result(5, "Hadez II") ])

        get "/api/v1/steam_collection_import_items/#{item.item_id}/igdb_candidates", headers: auth_headers_for(owner)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data").map { |c| [ c.fetch("igdb_id"), c.fetch("already_imported") ] })
          .to eq([ [ imported.igdb_id, true ], [ 5, false ] ])
        expect(igdb).to have_received(:search).with("Hadez™ (2020)", limit: 10)
      end

      it "searches q instead of the Steam name when given" do
        allow(igdb).to receive(:search).with("Custom", limit: 10).and_return([ igdb_result(7, "Custom") ])

        get "/api/v1/steam_collection_import_items/#{item.item_id}/igdb_candidates",
          params: { q: "Custom" }, headers: auth_headers_for(owner)

        expect(json.fetch("data").map { |c| c.fetch("igdb_id") }).to eq([ 7 ])
      end

      it "maps an IGDB outage to 502" do
        allow(igdb).to receive(:search).and_raise(Igdb::Client::RequestError, "boom")

        get "/api/v1/steam_collection_import_items/#{item.item_id}/igdb_candidates", headers: auth_headers_for(owner)

        expect(response).to have_http_status(:bad_gateway)
        expect(json.fetch("error")).to eq("igdb_request_failed")
      end

      it "is forbidden for another member" do
        get "/api/v1/steam_collection_import_items/#{item.item_id}/igdb_candidates", headers: auth_headers_for(other_user)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

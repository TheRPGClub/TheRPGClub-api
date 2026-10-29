# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the server-side Completionator import workflow (#291):
# CSV upload on create, advance (match, auto-add, auto-skip), and the item
# endpoints match / add_completion / update_completion / skip /
# igdb_candidates. Ports the bot's completionator-workflow.service.ts.
RSpec.describe "api/v1/completionator import workflow", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "POST /api/v1/users/:user_id/completionator_imports with csv_text" do
    let(:csv_text) do
      "Name,Platform,Region,Type,Time,Date\n" \
        "Chrono Trigger,Super Nintendo,North America,Core Game,25h:30m:00s,3/7/2021\n" \
        "\"Final Fantasy VII, Remake\",PlayStation 4,,Completionated,,\n"
    end

    it "parses the export server-side into pending items" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: csv_text, source_filename: "export.csv" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("total_count" => 2, "source_filename" => "export.csv", "status" => "active")

      items = RpgClubCompletionatorImport.find(json.dig("data", "import_id")).items.order(:row_index)
      expect(items.map(&:row_index)).to eq([ 2, 3 ])
      expect(items.first).to have_attributes(
        game_title: "Chrono Trigger", platform_name: "Super Nintendo", region_name: "North America",
        source_type: "Core Game", time_text: "25h:30m:00s", completion_type: "Main Story", status: "pending"
      )
      expect(items.first.playtime_hrs).to eq(25.5)
      expect(items.first.completed_at.to_date).to eq(Date.new(2021, 3, 7))
      expect(items.second).to have_attributes(game_title: "Final Fantasy VII, Remake", completion_type: "Completionist")
    end

    it "422s with invalid_csv on a malformed or empty export, creating nothing" do
      expect {
        post "/api/v1/users/#{owner.user_id}/completionator_imports",
          params: { data: { csv_text: "Name,Platform,Region,Type,Time,Date\n\"broken,PC,,,,\n" } },
          headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubCompletionatorImport, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_csv")
      expect(json.dig("errors", 0, "message")).to be_present

      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: "Name,Platform,Region,Type,Time,Date\n" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_csv")
      expect(json.dig("errors", 0, "message")).to match(/no data rows/)
    end

    it "reports a whole-file invalid_csv error at row_index 1, column file, as the collection CSV does" do
      [ "Name,Platform,Region,Type,Time,Date\n\"broken,PC,,,,\n", "Name,Platform,Region,Type,Time,Date\n" ].each do |text|
        post "/api/v1/users/#{owner.user_id}/completionator_imports",
          params: { data: { csv_text: text } }, headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("errors").sole).to include("row_index" => 1, "column" => "file")
      end
    end

    it "forbids another user" do
      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: csv_text } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  # Shared GameDB fixtures. Titles carry a random suffix so the matcher only
  # ever sees this example's games. Standard platforms are stubbed out so the
  # platform option list is just the game's platforms.
  let(:tag) { SecureRandom.hex(4) }
  let(:import) { create(:completionator_import, user: owner) }
  let!(:ps4) { create(:platform, platform_name: "PlayStation 4") }
  let!(:switch) { create(:platform, platform_name: "Switch") }
  let!(:windows) { create(:platform, platform_name: "Windows") }

  before { stub_const("Imports::CompletionatorWorkflow::STANDARD_PLATFORM_IDS", []) }

  def game_on(title, *platforms)
    create(:game, title: title).tap do |game|
      platforms.each { |platform| GamedbGamePlatform.create!(game_id: game.game_id, platform_id: platform.platform_id) }
    end
  end

  def item(**attrs)
    create(:completionator_import_item, import: import, **attrs)
  end

  def advance(as: owner)
    post "/api/v1/completionator_imports/#{import.import_id}/advance", headers: auth_headers_for(as), as: :json
  end

  describe "POST /api/v1/completionator_imports/:id/advance" do
    it "auto-adds a single match with a mapped platform, then stops at an ambiguous row" do
      game = game_on("Okami #{tag}", ps4, switch)
      game_on("Persona #{tag} Golden", ps4)
      game_on("Persona #{tag} Royal", ps4)
      auto = item(row_index: 1, game_title: "Okami #{tag}", platform_name: "PlayStation 4",
        completion_type: "Main Story", completed_at: Time.utc(2021, 3, 7), playtime_hrs: 30.5)
      ambiguous = item(row_index: 2, game_title: "Persona #{tag}", platform_name: "PlayStation 4")

      expect { advance }.to change(UserGameCompletion, :count).by(1)

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data).to include("auto_processed" => 1, "next_step" => "choose_game", "match_confidence" => "fuzzy",
        "existing_completion" => nil, "diff" => nil, "form" => nil, "game" => nil)
      expect(data.dig("item", "item_id")).to eq(ambiguous.item_id)
      expect(data.dig("import", "current_index")).to eq(2)
      expect(data.fetch("candidates").map { |candidate| candidate["title"] })
        .to contain_exactly("Persona #{tag} Golden", "Persona #{tag} Royal")
      expect(data.dig("counts", "by_status")).to include("added" => 1, "pending" => 1)
      expect(data.dig("counts", "import_id")).to eq(import.import_id)
      expect(data.fetch("candidates").first.keys).to contain_exactly("game_id", "title", "cover_url")

      completion = UserGameCompletion.find_by!(user_id: owner.user_id, gamedb_game_id: game.game_id)
      expect(completion).to have_attributes(completion_type: "Main Story", platform_id: ps4.platform_id)
      expect(completion.completed_at.to_date).to eq(Date.new(2021, 3, 7))
      expect(completion.final_playtime_hrs).to eq(30.5)
      expect(auto.reload).to have_attributes(status: "added", gamedb_game_id: game.game_id,
        completion_id: completion.completion_id)
    end

    it "auto-adds when the date is unknown, keeping completed_at null" do
      game_on("Celeste #{tag}", windows)
      added = item(game_title: "Celeste #{tag}", platform_name: "PC", completion_type: "Completionist")

      advance

      expect(json.fetch("data")).to include("item" => nil, "auto_processed" => 1)
      expect(json.dig("data", "import", "status")).to eq("completed")
      completion = UserGameCompletion.find(added.reload.completion_id)
      expect(completion).to have_attributes(completed_at: nil, completion_type: "Completionist",
        platform_id: windows.platform_id)
    end

    it "creates the missing release when the mapped platform is not on the game" do
      ww = GamedbRegion.find_by(region_code: "WW") || create(:region, region_code: "WW", region_name: "Worldwide")
      game = game_on("Hades #{tag}", windows)
      added = item(game_title: "Hades #{tag}", platform_name: "Nintendo Switch")

      expect { advance }.to change(GamedbRelease, :count).by(1)

      release = GamedbRelease.find_by!(game_id: game.game_id, platform_id: switch.platform_id)
      expect(release.region_id).to eq(ww.region_id)
      expect(UserGameCompletion.find(added.reload.completion_id).platform_id).to eq(switch.platform_id)
    end

    it "offers the add form when the platform cannot be resolved" do
      game = game_on("Tunic #{tag}", windows, switch)
      pending_item = item(game_title: "Tunic #{tag}", platform_name: "Commodore 64",
        completion_type: "Main Story", completed_at: Time.utc(2022, 5, 1), playtime_hrs: 12)

      expect { advance }.not_to change(UserGameCompletion, :count)

      data = json.fetch("data")
      expect(data).to include("next_step" => "add_completion", "auto_processed" => 0)
      expect(data.dig("game", "game_id")).to eq(game.game_id)
      expect(data.fetch("form")).to include(
        "completion_type" => "Main Story", "platform_id" => nil, "creates_release" => false,
        "date_choice" => "csv", "final_playtime_hours" => 12.0
      )
      expect(data.dig("form", "platforms").map { |platform| platform["platform_id"] })
        .to contain_exactly(windows.platform_id, switch.platform_id)
      expect(pending_item.reload).to have_attributes(status: "pending", gamedb_game_id: game.game_id)
    end

    it "auto-skips a row matching an existing completion with nothing to update" do
      game = game_on("Inside #{tag}", windows)
      create(:completion, user: owner, game: game, completion_type: "Main Story",
        completed_at: Time.utc(2020, 1, 2), final_playtime_hrs: 4.2)
      skipped = item(game_title: "Inside #{tag}", completion_type: "Main Story",
        completed_at: Time.utc(2020, 1, 2), playtime_hrs: 4.5)

      expect { advance }.not_to change(UserGameCompletion, :count)

      expect(json.fetch("data")).to include("item" => nil, "auto_processed" => 1)
      expect(skipped.reload.status).to eq("skipped")
    end

    it "asks whether it is the same completion when both dates differ" do
      game = game_on("Limbo #{tag}", windows)
      existing = create(:completion, user: owner, game: game, completion_type: "Main Story",
        completed_at: Time.utc(2019, 6, 1), final_playtime_hrs: nil)
      row = item(game_title: "Limbo #{tag}", completion_type: "Completionist",
        completed_at: Time.utc(2023, 6, 1), playtime_hrs: 8)

      advance

      data = json.fetch("data")
      expect(data).to include("next_step" => "confirm_same")
      expect(data.dig("existing_completion", "completion_id")).to eq(existing.completion_id)
      expect(data.fetch("diff")).to eq("fields" => %w[type date playtime], "confirm_same" => true)
      expect(data.fetch("form")).to be_present
      expect(row.reload).to have_attributes(status: "pending", completion_id: existing.completion_id)
    end

    it "offers the update selection when the existing completion has no date" do
      game = game_on("Braid #{tag}", windows)
      create(:completion, user: owner, game: game, completion_type: "Main Story", final_playtime_hrs: 3)
      game.user_game_completions.update_all(completed_at: nil)
      item(game_title: "Braid #{tag}", completion_type: "Main Story", completed_at: Time.utc(2023, 1, 1),
        playtime_hrs: 3.5)

      advance

      expect(json.fetch("data")).to include("next_step" => "update_completion",
        "diff" => { "fields" => %w[date], "confirm_same" => false })
    end

    it "reuses an item's matched game instead of searching again" do
      game = game_on("Matched #{tag}", windows, switch)
      row = item(game_title: "Something unmatchable #{tag}", gamedb_game_id: game.game_id)

      advance

      expect(json.fetch("data")).to include("next_step" => "add_completion", "candidates" => [])
      expect(json.dig("data", "item", "item_id")).to eq(row.item_id)
    end

    it "completes the import once no pending row is left" do
      item(status: "skipped")

      advance

      expect(json.fetch("data")).to include("item" => nil, "next_step" => nil, "auto_processed" => 0)
      expect(json.dig("data", "import", "status")).to eq("completed")
      expect(import.reload.status).to eq("completed")
    end

    it "stops after AUTO_LIMIT automatic rows, leaving the import active" do
      stub_const("Imports::CompletionatorWorkflow::AUTO_LIMIT", 1)
      game_on("Gris #{tag}", windows)
      game_on("Abzu #{tag}", windows)
      item(row_index: 1, game_title: "Gris #{tag}", platform_name: "PC")
      item(row_index: 2, game_title: "Abzu #{tag}", platform_name: "PC")

      advance

      expect(json.fetch("data")).to include("auto_processed" => 1, "item" => nil)
      expect(json.dig("data", "import", "status")).to eq("active")
      expect(import.items.where(status: "pending").count).to eq(1)
    end

    it "responds as if applied but rolls everything back in test_mode" do
      test_import = create(:completionator_import, user: owner, test_mode: true)
      game_on("Journey #{tag}", windows)
      row = create(:completionator_import_item, import: test_import, game_title: "Journey #{tag}", platform_name: "PC")

      expect {
        post "/api/v1/completionator_imports/#{test_import.import_id}/advance", headers: auth_headers_for(owner), as: :json
      }.not_to change(UserGameCompletion, :count)

      expect(json.fetch("data")).to include("auto_processed" => 1, "item" => nil)
      expect(row.reload.status).to eq("pending")
      expect(test_import.reload.status).to eq("active")
    end

    it "409s unless the import is active" do
      import.update!(status: "paused")

      advance

      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("import_not_active")
    end

    it "forbids another user" do
      advance(as: other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  def item_post(row, action, data = nil, as: owner, **fields)
    data ||= fields.presence
    params = data ? { data: data } : {}
    post "/api/v1/completionator_import_items/#{row.item_id}/#{action}",
      params: params, headers: auth_headers_for(as), as: :json
  end

  describe "POST /api/v1/completionator_import_items/:id/match" do
    it "matches a GameDB game and returns the review" do
      game = game_on("Picked #{tag}", windows, switch)
      row = item(game_title: "Unmatchable #{tag}", platform_name: "Commodore 64")

      item_post(row, "match", game_id: game.game_id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("next_step" => "add_completion")
      expect(json.dig("data", "game", "game_id")).to eq(game.game_id)
      expect(json.dig("data", "import", "import_id")).to eq(import.import_id)
      expect(row.reload.gamedb_game_id).to eq(game.game_id)
    end

    it "auto-adds when the matched game has the mapped platform" do
      game = game_on("Picked #{tag}", windows)
      row = item(game_title: "Unmatchable #{tag}", platform_name: "PC")

      expect { item_post(row, "match", game_id: game.game_id) }.to change(UserGameCompletion, :count).by(1)

      expect(json.fetch("data")).to include("next_step" => "auto_added")
      expect(json.dig("data", "item", "status")).to eq("added")
    end

    it "imports an IGDB id through Imports::IgdbGameResolver" do
      game = game_on("From IGDB #{tag}", windows, switch)
      resolver = instance_double(Imports::IgdbGameResolver)
      allow(Imports::IgdbGameResolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:resolve).with(1234)
        .and_return(Imports::IgdbGameResolver::Result.new(game: game, created: true, error: nil))
      row = item(game_title: "Unmatchable #{tag}")

      item_post(row, "match", igdb_id: 1234)

      expect(response).to have_http_status(:ok)
      expect(row.reload.gamedb_game_id).to eq(game.game_id)
    end

    it "maps IGDB resolver errors" do
      resolver = instance_double(Imports::IgdbGameResolver)
      allow(Imports::IgdbGameResolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:resolve)
        .and_return(Imports::IgdbGameResolver::Result.new(game: nil, created: false, error: "igdb_game_not_found"))
      row = item

      item_post(row, "match", igdb_id: 99)

      expect(response).to have_http_status(:not_found)
      expect(json.fetch("error")).to eq("igdb_game_not_found")
    end

    it "rolls the IGDB import back with the match in test_mode, like the CSV and Steam apply" do
      test_import = create(:completionator_import, user: owner, test_mode: true)
      row = create(:completionator_import_item, import: test_import, game_title: "Unmatchable #{tag}")
      importer = instance_double(Gamedb::IgdbGameImporter)
      allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer)
      allow(importer).to receive(:import!).with(5151) do
        game = game_on("Imported #{tag}", windows, switch)
        Gamedb::IgdbGameImporter::Result.new(game: game, created: true, images: [])
      end

      expect { item_post(row, "match", igdb_id: 5151) }.not_to change(GamedbGame, :count)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "game", "title")).to eq("Imported #{tag}")
      expect(row.reload.gamedb_game_id).to be_nil
    end

    it "404s for an unknown game and 422s without exactly one of game_id or igdb_id" do
      row = item

      item_post(row, "match", game_id: 999_999_999)
      expect(response).to have_http_status(:not_found)
      expect(json.fetch("error")).to eq("game_not_found")

      item_post(row, "match", {})
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("game_id_or_igdb_id_required")

      item_post(row, "match", game_id: 1, igdb_id: 2)
      expect(json.fetch("error")).to eq("game_id_or_igdb_id_required")
    end

    it "409s for an item that is no longer pending, or an import that is not active" do
      game = game_on("Done #{tag}", windows)
      row = item(status: "added")

      item_post(row, "match", game_id: game.game_id)
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("item_not_pending")

      paused = item
      import.update!(status: "paused")
      item_post(paused, "skip")
      expect(response).to have_http_status(:conflict)
      expect(json.fetch("error")).to eq("import_not_active")
    end

    it "forbids another user" do
      game = game_on("Picked #{tag}", windows)
      row = item

      item_post(row, "match", { game_id: game.game_id }, as: other_user)

      expect(response).to have_http_status(:forbidden)
      expect(row.reload.gamedb_game_id).to be_nil
    end
  end

  describe "POST /api/v1/completionator_import_items/:id/add_completion" do
    it "creates the completion from the submitted form" do
      game = game_on("Added #{tag}", windows, switch)
      row = item(game_title: "Added #{tag}", gamedb_game_id: game.game_id, playtime_hrs: 10)

      item_post(row, "add_completion", completion_type: "Completionist", platform_id: switch.platform_id,
        completed_at: "2024-02-03", final_playtime_hours: 11.25)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("added")
      completion = UserGameCompletion.find(row.reload.completion_id)
      expect(completion).to have_attributes(user_id: owner.user_id, gamedb_game_id: game.game_id,
        completion_type: "Completionist", platform_id: switch.platform_id, final_playtime_hrs: 11.25)
      expect(completion.completed_at.to_date).to eq(Date.new(2024, 2, 3))
    end

    it "creates the missing release for the item's mapped platform" do
      create(:region, region_code: "WW", region_name: "Worldwide") unless GamedbRegion.exists?(region_code: "WW")
      game = game_on("Release #{tag}", windows)
      row = item(game_title: "Release #{tag}", gamedb_game_id: game.game_id, platform_name: "Switch")

      expect {
        item_post(row, "add_completion", completion_type: "Main Story", platform_id: switch.platform_id,
          completed_at: nil)
      }.to change(GamedbRelease, :count).by(1)

      expect(GamedbRelease.where(game_id: game.game_id, platform_id: switch.platform_id)).to exist
      expect(UserGameCompletion.find(row.reload.completion_id).completed_at).to be_nil
    end

    it "does not create a release for an unmapped platform choice, or with no platform" do
      game = game_on("NoRelease #{tag}", windows)
      row = item(game_title: "NoRelease #{tag}", gamedb_game_id: game.game_id, platform_name: "PC")

      expect {
        item_post(row, "add_completion", completion_type: "Main Story", platform_id: switch.platform_id)
      }.not_to change(GamedbRelease, :count)
      expect(response).to have_http_status(:ok)

      other = item(game_title: "NoRelease #{tag}", gamedb_game_id: game.game_id)
      item_post(other, "add_completion", completion_type: "Main Story", platform_id: nil)
      expect(UserGameCompletion.find(other.reload.completion_id).platform_id).to be_nil
    end

    it "422s without a matched game, or with an invalid type, platform or date" do
      unmatched = item
      item_post(unmatched, "add_completion", completion_type: "Main Story")
      expect(json.fetch("error")).to eq("no_game_matched")

      game = game_on("Bad #{tag}", windows)
      row = item(gamedb_game_id: game.game_id)
      item_post(row, "add_completion", completion_type: "Speedrun")
      expect(json.fetch("error")).to eq("invalid_completion_type")
      item_post(row, "add_completion", platform_id: 999_999_999)
      expect(json.fetch("error")).to eq("invalid_platform")
      item_post(row, "add_completion", completed_at: "not a date")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_completed_at")
      expect(row.reload.status).to eq("pending")
    end

    it "rolls the completion back in test_mode" do
      test_import = create(:completionator_import, user: owner, test_mode: true)
      game = game_on("Dry #{tag}", windows)
      row = create(:completionator_import_item, import: test_import, gamedb_game_id: game.game_id)

      expect { item_post(row, "add_completion", completion_type: "Main Story") }.not_to change(UserGameCompletion, :count)
      expect(json.dig("data", "status")).to eq("added")
      expect(row.reload.status).to eq("pending")
    end

    it "forbids another user" do
      game = game_on("Other #{tag}", windows)
      row = item(gamedb_game_id: game.game_id)

      expect { item_post(row, "add_completion", { completion_type: "Main Story" }, as: other_user) }
        .not_to change(UserGameCompletion, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/completionator_import_items/:id/update_completion" do
    let(:game) { game_on("Update #{tag}", windows) }
    let!(:existing) do
      create(:completion, user: owner, game: game, completion_type: "Main Story",
        completed_at: Time.utc(2019, 1, 1), final_playtime_hrs: 5)
    end
    let(:row) do
      item(gamedb_game_id: game.game_id, completion_id: existing.completion_id, completion_type: "Completionist",
        completed_at: Time.utc(2020, 2, 2), playtime_hrs: 9)
    end

    it "applies only the selected fields" do
      item_post(row, "update_completion", fields: %w[type playtime])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("updated")
      expect(existing.reload).to have_attributes(completion_type: "Completionist", final_playtime_hrs: 9)
      expect(existing.completed_at.to_date).to eq(Date.new(2019, 1, 1))
    end

    it "updates the date" do
      item_post(row, "update_completion", fields: %w[date])

      expect(existing.reload.completed_at.to_date).to eq(Date.new(2020, 2, 2))
    end

    it "skips the item when no selected field differs" do
      existing.update!(completion_type: "Completionist")

      item_post(row, "update_completion", fields: %w[type])

      expect(json.dig("data", "status")).to eq("skipped")
    end

    it "422s on unknown or missing fields, and without an existing completion" do
      item_post(row, "update_completion", fields: %w[title])
      expect(json.fetch("error")).to eq("invalid_fields")
      item_post(row, "update_completion", fields: [])
      expect(json.fetch("error")).to eq("invalid_fields")

      bare = item(gamedb_game_id: game.game_id)
      item_post(bare, "update_completion", fields: %w[type])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("no_existing_completion")
    end

    it "forbids another user" do
      item_post(row, "update_completion", { fields: %w[type] }, as: other_user)

      expect(response).to have_http_status(:forbidden)
      expect(existing.reload.completion_type).to eq("Main Story")
    end
  end

  describe "POST /api/v1/completionator_import_items/:id/skip" do
    it "skips the item" do
      row = item

      item_post(row, "skip")

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("skipped")
      expect(row.reload.status).to eq("skipped")
    end

    it "forbids another user" do
      row = item

      item_post(row, "skip", nil, as: other_user)

      expect(response).to have_http_status(:forbidden)
      expect(row.reload.status).to eq("pending")
    end
  end

  describe "GET /api/v1/completionator_import_items/:id/igdb_candidates" do
    let(:client) { instance_double(Igdb::Client) }

    before { allow(Igdb::Client).to receive(:new).and_return(client) }

    it "searches IGDB by the item title's variants and flags games already in GameDB" do
      create(:game, igdb_id: 11)
      row = item(game_title: "Okami HD (2012)")
      allow(client).to receive(:search).with("Okami HD (2012)", limit: 10).and_return([])
      allow(client).to receive(:search).with("Okami HD", limit: 10)
        .and_return([ { igdb_id: 11, name: "Okami" }, { igdb_id: 12, name: "Okami HD" } ])

      get "/api/v1/completionator_import_items/#{row.item_id}/igdb_candidates", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        { "igdb_id" => 11, "name" => "Okami", "already_imported" => true },
        { "igdb_id" => 12, "name" => "Okami HD", "already_imported" => false }
      ])
    end

    it "uses q when given and maps IGDB failures" do
      row = item
      allow(client).to receive(:search).with("Zelda", limit: 10).and_raise(Igdb::Client::RequestError, "down")

      get "/api/v1/completionator_import_items/#{row.item_id}/igdb_candidates", params: { q: "Zelda" },
        headers: auth_headers_for(owner)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.fetch("error")).to eq("igdb_request_failed")
    end

    it "forbids another user" do
      row = item

      get "/api/v1/completionator_import_items/#{row.item_id}/igdb_candidates", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

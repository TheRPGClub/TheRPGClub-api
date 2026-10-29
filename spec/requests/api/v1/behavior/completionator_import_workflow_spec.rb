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
      expect(items.map(&:row_index)).to eq([ 1, 2 ])
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

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "invalid_csv")
      expect(json.fetch("message")).to be_present

      post "/api/v1/users/#{owner.user_id}/completionator_imports",
        params: { data: { csv_text: "Name,Platform,Region,Type,Time,Date\n" } },
        headers: auth_headers_for(owner), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("error" => "invalid_csv")
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
      expect(data).to include("auto_processed" => 1, "done" => false, "next_step" => "choose_game",
        "existing_completion" => nil, "diff" => nil, "form" => nil, "game" => nil)
      expect(data.dig("item", "item_id")).to eq(ambiguous.item_id)
      expect(data.dig("import", "current_index")).to eq(2)
      expect(data.fetch("candidates").map { |candidate| candidate["title"] })
        .to contain_exactly("Persona #{tag} Golden", "Persona #{tag} Royal")
      expect(data.fetch("counts")).to include("added" => 1, "pending" => 1)

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

      expect(json.fetch("data")).to include("done" => true, "item" => nil, "auto_processed" => 1)
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
      expect(data).to include("next_step" => "add_completion", "auto_processed" => 0, "done" => false)
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

      expect(json.fetch("data")).to include("done" => true, "auto_processed" => 1)
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

      expect(json.fetch("data")).to include("done" => true, "item" => nil, "next_step" => nil, "auto_processed" => 0)
      expect(json.dig("data", "import", "status")).to eq("completed")
      expect(import.reload.status).to eq("completed")
    end

    it "stops after AUTO_LIMIT automatic rows and reports it is not done" do
      stub_const("Imports::CompletionatorWorkflow::AUTO_LIMIT", 1)
      game_on("Gris #{tag}", windows)
      game_on("Abzu #{tag}", windows)
      item(row_index: 1, game_title: "Gris #{tag}", platform_name: "PC")
      item(row_index: 2, game_title: "Abzu #{tag}", platform_name: "PC")

      advance

      expect(json.fetch("data")).to include("auto_processed" => 1, "done" => false, "item" => nil)
      expect(import.items.where(status: "pending").count).to eq(1)
    end

    it "responds as if applied but rolls everything back in test_mode" do
      test_import = create(:completionator_import, user: owner, test_mode: true)
      game_on("Journey #{tag}", windows)
      row = create(:completionator_import_item, import: test_import, game_title: "Journey #{tag}", platform_name: "PC")

      expect {
        post "/api/v1/completionator_imports/#{test_import.import_id}/advance", headers: auth_headers_for(owner), as: :json
      }.not_to change(UserGameCompletion, :count)

      expect(json.fetch("data")).to include("auto_processed" => 1, "done" => true)
      expect(row.reload.status).to eq("pending")
      expect(test_import.reload.status).to eq("active")
    end

    it "forbids another user" do
      advance(as: other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

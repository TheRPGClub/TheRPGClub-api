# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the journal endpoints: the per-user grid, per-game status,
# entry search, contributors, the game-scoped list and the single-entry CRUD.
# Reads are open to any authenticated principal; create/update/destroy are
# gated to the owner (or the service).
RSpec.describe "api/v1/journal behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/journal" do
    it "lists one row per journaled game with entry counts, ordered by title" do
      prefix = "jgrid #{SecureRandom.hex(4)}"
      game_a = create(:game, title: "#{prefix} aaa")
      game_b = create(:game, title: "#{prefix} bbb")
      create(:journal_entry, user: owner, game: game_a)
      create(:journal_entry, user: owner, game: game_a)
      create(:journal_entry, user: owner, game: game_b)
      create(:journal_entry, user: other_user)

      get "/api/v1/users/#{owner.user_id}/journal", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.length).to eq(2)
      expect(data.map { |row| row.dig("game", "game_id") }).to eq([ game_a.game_id, game_b.game_id ])
      expect(data.first).to include("entry_count" => 2)
      expect(data.first.fetch("last_entry_at")).to be_present
      expect(json.dig("meta", "count")).to eq(2)
    end

    it "selects games via q but keeps the full per-game totals" do
      game_a = create(:game)
      game_b = create(:game)
      create(:journal_entry, user: owner, game: game_a, entry_body: "found the jqfilter hidden path")
      create(:journal_entry, user: owner, game: game_a, entry_body: "plain follow-up")
      create(:journal_entry, user: owner, game: game_b, entry_body: "nothing to see")

      get "/api/v1/users/#{owner.user_id}/journal",
        params: { q: "JQFILTER HIDDEN" }, headers: service_headers

      data = json.fetch("data")
      expect(data.map { |row| row.dig("game", "game_id") }).to eq([ game_a.game_id ])
      expect(data.first).to include("entry_count" => 2)
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "filters to a single game with game_id" do
      game_a = create(:game)
      game_b = create(:game)
      create(:journal_entry, user: owner, game: game_a)
      create(:journal_entry, user: owner, game: game_b)

      get "/api/v1/users/#{owner.user_id}/journal",
        params: { game_id: game_b.game_id }, headers: service_headers

      expect(json.fetch("data").map { |row| row.dig("game", "game_id") }).to eq([ game_b.game_id ])
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/journal"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/:user_id/journal/status" do
    it "returns per-game counts for the requested ids, omitting games without entries" do
      game_a = create(:game)
      game_b = create(:game)
      unjournaled_game = create(:game)
      create_list(:journal_entry, 2, user: owner, game: game_a)
      create(:journal_entry, user: owner, game: game_b)
      create(:journal_entry, user: other_user, game: unjournaled_game)

      get "/api/v1/users/#{owner.user_id}/journal/status",
        params: { game_ids: [ game_a.game_id, game_b.game_id, unjournaled_game.game_id ] },
        headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      rows = json.fetch("data").index_by { |r| r.fetch("gamedb_game_id") }
      expect(rows.keys).to contain_exactly(game_a.game_id, game_b.game_id)
      expect(rows.fetch(game_a.game_id)).to include("entry_count" => 2)
      expect(rows.fetch(game_a.game_id).fetch("last_entry_at")).to be_present
      expect(rows.fetch(game_b.game_id)).to include("entry_count" => 1)
    end

    it "returns an empty list when no game_ids are given" do
      get "/api/v1/users/#{owner.user_id}/journal/status", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([])
    end
  end

  describe "POST /api/v1/users/:user_id/journal" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, entry_title: "Session 1", entry_body: "Met the king." } } }

    it "creates an entry for the owner with the game embedded" do
      expect {
        post "/api/v1/users/#{owner.user_id}/journal",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameJournalEntry.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "entry_title" => "Session 1",
        "entry_body" => "Met the king."
      )
      expect(json.dig("data", "game", "game_id")).to eq(game.game_id)
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/journal", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/journal",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserGameJournalEntry, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s when entry_body is missing" do
      post "/api/v1/users/#{owner.user_id}/journal",
        params: { data: { gamedb_game_id: game.game_id } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/journal",
        params: { data: { gamedb_game_id: 999_999_999, entry_body: "text" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/journal", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/journal_entries" do
    it "searches entries by q across title and body with game and author embedded" do
      title_match = create(:journal_entry, user: owner, entry_title: "The JSRCH Chronicles", entry_body: "plain")
      body_match = create(:journal_entry, user: other_user, entry_body: "we found the jsrch relic")
      create(:journal_entry, user: owner, entry_body: "unrelated")

      get "/api/v1/journal_entries", params: { q: "jsrch" }, headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |e| e.fetch("entry_id") }
      expect(ids).to contain_exactly(title_match.entry_id, body_match.entry_id)
      row = json.fetch("data").find { |e| e.fetch("entry_id") == title_match.entry_id }
      expect(row.fetch("game")).to include("game_id" => title_match.gamedb_game_id)
      expect(row.fetch("user")).to include("user_id" => owner.user_id)
    end

    it "narrows with the user_id and game_id filters" do
      mine = create(:journal_entry, user: owner, entry_body: "jflt body one")
      create(:journal_entry, user: other_user, entry_body: "jflt body two")

      get "/api/v1/journal_entries",
        params: { q: "jflt", user_id: owner.user_id, game_id: mine.gamedb_game_id },
        headers: service_headers

      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ mine.entry_id ])
    end

    it "requires authentication" do
      get "/api/v1/journal_entries"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/journal_entries/contributors" do
    it "lists journaling members with counts, excluding bots and departed members" do
      contributor = create(:user)
      game_a = create(:game)
      game_b = create(:game)
      create_list(:journal_entry, 2, user: contributor, game: game_a)
      create(:journal_entry, user: contributor, game: game_b)
      bot = create(:user, is_bot: true)
      departed = create(:user, server_left_at: Time.current)
      create(:journal_entry, user: bot)
      create(:journal_entry, user: departed)

      get "/api/v1/journal_entries/contributors", headers: auth_headers_for(contributor)

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |r| r.fetch("user_id") }
      expect(ids).to include(contributor.user_id)
      expect(ids).not_to include(bot.user_id, departed.user_id)
      row = json.fetch("data").find { |r| r.fetch("user_id") == contributor.user_id }
      expect(row).to include("username" => contributor.username, "game_count" => 2, "entry_count" => 3)
    end
  end

  describe "GET /api/v1/games/:id/journal" do
    it "lists the game's entries across users, newest first, with the author embedded" do
      game = create(:game)
      older = create(:journal_entry, user: owner, game: game, created_at: 2.days.ago)
      newer = create(:journal_entry, user: other_user, game: game, created_at: 1.day.ago)
      create(:journal_entry, user: owner)

      get "/api/v1/games/#{game.game_id}/journal", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ newer.entry_id, older.entry_id ])
      expect(json.dig("data", 0, "user")).to include("user_id" => other_user.user_id)
    end

    it "filters to a single author with user_id" do
      game = create(:game)
      mine = create(:journal_entry, user: owner, game: game)
      create(:journal_entry, user: other_user, game: game)

      get "/api/v1/games/#{game.game_id}/journal",
        params: { user_id: owner.user_id }, headers: service_headers

      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ mine.entry_id ])
    end
  end

  describe "GET /api/v1/journal_entries/:id" do
    it "shows an entry with its game to any authenticated user" do
      entry = create(:journal_entry, user: owner)

      get "/api/v1/journal_entries/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("entry_id" => entry.entry_id, "entry_body" => entry.entry_body)
      expect(json.dig("data", "game")).to include("game_id" => entry.gamedb_game_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/journal_entries/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/journal_entries/:id" do
    it "updates the owner's entry" do
      entry = create(:journal_entry, user: owner)

      patch "/api/v1/journal_entries/#{entry.entry_id}",
        params: { data: { entry_title: "Revised", entry_body: "Rewritten body." } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("entry_title" => "Revised", "entry_body" => "Rewritten body.")
      expect(entry.reload.entry_body).to eq("Rewritten body.")
    end

    it "allows the service" do
      entry = create(:journal_entry, user: owner)

      patch "/api/v1/journal_entries/#{entry.entry_id}",
        params: { data: { entry_title: "Service edit" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.entry_title).to eq("Service edit")
    end

    it "forbids a non-owner" do
      entry = create(:journal_entry, user: owner)

      patch "/api/v1/journal_entries/#{entry.entry_id}",
        params: { data: { entry_body: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.entry_body).not_to eq("hijacked")
    end

    it "404s for an unknown id (as the service)" do
      patch "/api/v1/journal_entries/999999999",
        params: { data: { entry_body: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "422s when entry_body is blanked" do
      entry = create(:journal_entry, user: owner)

      patch "/api/v1/journal_entries/#{entry.entry_id}",
        params: { data: { entry_body: "" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/journal_entries/:id" do
    it "deletes the owner's entry" do
      entry = create(:journal_entry, user: owner)

      delete "/api/v1/journal_entries/#{entry.entry_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameJournalEntry.exists?(entry.entry_id)).to be(false)
    end

    it "forbids a non-owner" do
      entry = create(:journal_entry, user: owner)

      delete "/api/v1/journal_entries/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameJournalEntry.exists?(entry.entry_id)).to be(true)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the now-playing endpoints: the per-user and game-scoped
# lists are open to any authenticated principal, the cross-member index is
# service/admin-only, and create/update/destroy are gated to the owner (or the
# service). `sort_order`/`note_updated_at`/`added_at` are server-managed on
# create; update accepts only `note`, `platform_id` and `sort_order`.
RSpec.describe "api/v1/now_playing behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/now_playing" do
    it "lists the user's entries by sort_order with embeds and journal aggregates" do
      platform = create(:platform)
      game = create(:game)
      first = create(:now_playing_entry, user: owner, game: game, platform: platform, note: "grinding")
      second = create(:now_playing_entry, user: owner)
      create(:now_playing_entry, user: other_user)
      create(:journal_entry, user: owner, game: game)

      get "/api/v1/users/#{owner.user_id}/now_playing", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data.map { |e| e.fetch("entry_id") }).to eq([ first.entry_id, second.entry_id ])
      expect(data.first).to include(
        "entry_id" => first.entry_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "platform_id" => platform.platform_id,
        "note" => "grinding",
        "sort_order" => 1,
        "has_journal_entry" => true,
        "journal_count" => 1
      )
      expect(data.first.fetch("game")).to include("game_id" => game.game_id)
      expect(data.first.fetch("platform")).to include("platform_id" => platform.platform_id)
      expect(data.last).to include("has_journal_entry" => false, "journal_count" => 0)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/now_playing"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/now_playing" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, note: "just started" } } }

    it "creates an entry for the owner, appending sort_order server-side" do
      create(:now_playing_entry, user: owner)

      expect {
        post "/api/v1/users/#{owner.user_id}/now_playing",
          params: { data: { gamedb_game_id: game.game_id, note: "just started", sort_order: 99 } },
          headers: auth_headers_for(owner), as: :json
      }.to change(UserNowPlaying.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "note" => "just started",
        # the client-sent 99 is stripped; the server appends after the existing entry
        "sort_order" => 2
      )
      expect(json.dig("data", "note_updated_at")).to be_present
      expect(json.dig("data", "game", "game_id")).to eq(game.game_id)
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/now_playing", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/now_playing",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserNowPlaying, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s when the game is already on the list (unique per user and game)" do
      create(:now_playing_entry, user: owner, game: game)

      post "/api/v1/users/#{owner.user_id}/now_playing",
        params: payload, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s once the user already has the maximum of 10 entries" do
      create_list(:now_playing_entry, 10, user: owner)

      post "/api/v1/users/#{owner.user_id}/now_playing",
        params: payload, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("maximum")
    end

    it "422s when the note exceeds 500 characters" do
      post "/api/v1/users/#{owner.user_id}/now_playing",
        params: { data: { gamedb_game_id: game.game_id, note: "x" * 501 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/now_playing",
        params: { data: { gamedb_game_id: 999_999_999 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when gamedb_game_id is missing" do
      pending "possible bug: the API accepts a now-playing entry with no gamedb_game_id " \
        "(column is nullable and the model has no presence validation) although the " \
        "documented contract requires it on create"

      post "/api/v1/users/#{owner.user_id}/now_playing",
        params: { data: { note: "no game" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/now_playing", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/now_playing" do
    it "lists active members' entries for the service, excluding bots and departed members" do
      game = create(:game)
      member_entry = create(:now_playing_entry, user: owner, game: game)
      create(:now_playing_entry, user: create(:user, is_bot: true), game: game)
      create(:now_playing_entry, user: create(:user, server_left_at: Time.current), game: game)

      get "/api/v1/now_playing", params: { game_ids: [ game.game_id ] }, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ member_entry.entry_id ])
      expect(json.dig("data", 0, "user")).to include("user_id" => owner.user_id)
      expect(json.dig("data", 0, "game")).to include("game_id" => game.game_id)
    end

    it "filters by q on the game title, case-insensitively" do
      game = create(:game, title: "npq special quest #{SecureRandom.hex(4)}")
      entry = create(:now_playing_entry, user: owner, game: game)
      create(:now_playing_entry, user: owner)

      get "/api/v1/now_playing", params: { q: "NPQ SPECIAL" }, headers: service_headers

      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ entry.entry_id ])
    end

    it "allows an admin user" do
      get "/api/v1/now_playing", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
    end

    it "forbids a regular user" do
      get "/api/v1/now_playing", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/games/:id/now_playing" do
    it "lists the game's entries with the playing user embedded" do
      game = create(:game)
      entry = create(:now_playing_entry, user: owner, game: game)
      create(:now_playing_entry, user: owner)

      get "/api/v1/games/#{game.game_id}/now_playing", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |e| e.fetch("entry_id") }).to eq([ entry.entry_id ])
      expect(json.dig("data", 0, "user")).to include("user_id" => owner.user_id)
    end
  end

  describe "GET /api/v1/now_playing/:id" do
    it "shows an entry with its user and game to any authenticated user" do
      entry = create(:now_playing_entry, user: owner)

      get "/api/v1/now_playing/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("entry_id" => entry.entry_id)
      expect(json.dig("data", "user")).to include("user_id" => owner.user_id)
      expect(json.dig("data", "game")).to include("game_id" => entry.gamedb_game_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/now_playing/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/now_playing/:id" do
    it "updates note and sort_order for the owner, ignoring non-writable columns" do
      entry = create(:now_playing_entry, user: owner)
      original_game_id = entry.gamedb_game_id
      other_game = create(:game)

      patch "/api/v1/now_playing/#{entry.entry_id}",
        params: { data: { note: "new note", sort_order: 5, gamedb_game_id: other_game.game_id } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "note" => "new note",
        "sort_order" => 5,
        # gamedb_game_id is not update-writable and stays unchanged
        "gamedb_game_id" => original_game_id
      )
      expect(json.dig("data", "note_updated_at")).to be_present
      expect(entry.reload.gamedb_game_id).to eq(original_game_id)
    end

    it "allows the service" do
      entry = create(:now_playing_entry, user: owner)

      patch "/api/v1/now_playing/#{entry.entry_id}",
        params: { data: { note: "service note" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.note).to eq("service note")
    end

    it "forbids a non-owner" do
      entry = create(:now_playing_entry, user: owner)

      patch "/api/v1/now_playing/#{entry.entry_id}",
        params: { data: { note: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.note).not_to eq("hijacked")
    end

    it "404s for an unknown id (as the service)" do
      patch "/api/v1/now_playing/999999999",
        params: { data: { note: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/now_playing/:id" do
    it "deletes the owner's entry" do
      entry = create(:now_playing_entry, user: owner)

      delete "/api/v1/now_playing/#{entry.entry_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserNowPlaying.exists?(entry.entry_id)).to be(false)
    end

    it "forbids a non-owner" do
      entry = create(:now_playing_entry, user: owner)

      delete "/api/v1/now_playing/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserNowPlaying.exists?(entry.entry_id)).to be(true)
    end
  end
end

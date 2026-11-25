# frozen_string_literal: true

require "rails_helper"

# Playtime and Manual Playtime (spec api#457, ticket api#458; ADR 0015).
# Reads are open to any signed-in caller; writes are the member's own, or a
# Superadmin's (or the bot's) for anyone. Ungated.
RSpec.describe "api/v1 playtime behavior", type: :request do
  let(:member) { create(:user) }
  let(:other) { create(:user) }
  let(:game) { create(:game) }
  let!(:windows) { create(:platform, platform_name: "PC (Microsoft Windows)") }
  let!(:switch) { create(:platform, platform_name: "Nintendo Switch") }

  def steam_playtime(user, minutes, game: self.game)
    account = create(:user_linked_account, user: user, provider: "steam")
    set = create(:achievement_set, provider: "steam", game: game, platform_label: "PC", title: "Steam set")
    create(:user_achievement_set_progress, linked_account: account, achievement_set: set, playtime_minutes: minutes)
  end

  def playtime_path(user = member) = "/api/v1/users/#{user.user_id}/games/#{game.game_id}/playtime"
  def manual_path(user = member) = "/api/v1/users/#{user.user_id}/games/#{game.game_id}/manual_playtimes"

  def add(minutes, platform: switch, mode: "add", as: member, user: member, note: nil)
    body = { platform_id: platform&.platform_id, minutes: minutes, mode: mode }
    body[:note] = note if note
    post manual_path(user), params: { data: body }, headers: auth_headers_for(as), as: :json
  end

  describe "GET /users/:user_id/games/:game_id/playtime" do
    it "shows any member the total, the breakdown and the mismatches" do
      steam_playtime(member, 600)
      entry = create(:manual_playtime, user: member, game: game, platform: windows, minutes: 30, note: "laptop")
      create(:manual_playtime, user: member, game: game, platform: nil, minutes: 15)

      get playtime_path, headers: auth_headers_for(other)

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data).to include("user_id" => member.user_id, "game_id" => game.game_id, "total_minutes" => 645,
        "open_playthrough" => nil)
      expect(data.dig("breakdown", "provider_sets")).to contain_exactly(include(
        "provider" => "steam", "title" => "Steam set", "platform_label" => "PC", "platform_id" => windows.platform_id,
        "platform_name" => "PC (Microsoft Windows)", "minutes" => 600, "counted" => true
      ))
      expect(data.dig("breakdown", "manual_entries")).to match([
        include("id" => entry.id, "platform_id" => windows.platform_id, "platform_name" => "PC (Microsoft Windows)",
          "minutes" => 30, "note" => "laptop", "origin" => "member", "keeps_over_provider" => nil),
        include("platform_id" => nil, "platform_name" => nil, "minutes" => 15)
      ])
      expect(data.fetch("mismatches")).to eq([ {
        "platform_id" => windows.platform_id, "platform_name" => "PC (Microsoft Windows)", "provider" => "steam",
        "provider_minutes" => 600, "manual_playtime_id" => entry.id, "manual_minutes" => 30
      } ])
    end

    it "is zero with an empty breakdown for a game with no Playtime" do
      get playtime_path, headers: service_headers

      expect(json.fetch("data")).to include("total_minutes" => 0, "mismatches" => [],
        "breakdown" => { "provider_sets" => [], "manual_entries" => [] })
    end

    it "is 404 for an unknown game or member" do
      get "/api/v1/users/#{member.user_id}/games/0/playtime", headers: service_headers
      expect(response).to have_http_status(:not_found)

      get "/api/v1/users/1/games/#{game.game_id}/playtime", headers: service_headers
      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get playtime_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /users/:user_id/games/:game_id/manual_playtimes" do
    it "adds time to the platform's entry, creating it the first time" do
      add(90, note: "save file")
      add(30)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "total_minutes")).to eq(120)
      expect(json.dig("data", "breakdown", "manual_entries")).to contain_exactly(
        include("platform_id" => switch.platform_id, "minutes" => 120, "note" => "save file", "origin" => "member")
      )
    end

    it "sets the total, replacing the minutes" do
      add(90)
      add(45, mode: "set")

      expect(json.dig("data", "breakdown", "manual_entries").map { |entry| entry["minutes"] }).to eq([ 45 ])
    end

    it "keeps one entry per platform, Other included" do
      add(10, platform: nil)
      add(5, platform: nil)
      add(20, platform: windows)

      entries = json.dig("data", "breakdown", "manual_entries")
      expect(entries.map { |entry| [ entry["platform_id"], entry["minutes"] ] })
        .to eq([ [ windows.platform_id, 20 ], [ nil, 15 ] ])
    end

    it "refuses negative or non-whole minutes, an unknown mode or platform, and a long note" do
      [ { minutes: -1 }, { minutes: 1.5 }, { minutes: "x" }, { mode: "double" }, { platform_id: 0 },
        { note: "x" * 281 } ].each do |change|
        body = { platform_id: switch.platform_id, minutes: 10, mode: "add" }.merge(change)
        post manual_path, params: { data: body }, headers: auth_headers_for(member), as: :json

        expect(response).to have_http_status(:unprocessable_content), change.inspect
      end
      expect(UserGameManualPlaytime.count).to eq(0)
    end

    it "is the member's own: another member is refused, a Superadmin and the bot may write for anyone" do
      add(10, as: other)
      expect(response).to have_http_status(:forbidden)

      post manual_path, params: { data: { platform_id: nil, minutes: 10, mode: "add" } },
        headers: auth_headers_for(other, is_dev: true), as: :json
      expect(response).to have_http_status(:ok)

      post manual_path, params: { data: { platform_id: nil, minutes: 5, mode: "add" } }, headers: service_headers,
        as: :json
      expect(json.dig("data", "total_minutes")).to eq(15)
    end
  end

  describe "PATCH and DELETE /manual_playtimes/:id" do
    let!(:entry) { create(:manual_playtime, user: member, game: game, platform: switch, minutes: 60) }

    it "changes the minutes, note and platform, and returns the game's Playtime" do
      patch "/api/v1/manual_playtimes/#{entry.id}", params: { data: { minutes: 75, note: "replay", platform_id: nil } },
        headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "breakdown", "manual_entries"))
        .to contain_exactly(include("id" => entry.id, "minutes" => 75, "note" => "replay", "platform_id" => nil))
    end

    it "deletes the entry" do
      delete "/api/v1/manual_playtimes/#{entry.id}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "total_minutes")).to eq(0)
      expect(UserGameManualPlaytime.exists?(entry.id)).to be(false)
    end

    it "refuses another member, but not a Superadmin" do
      patch "/api/v1/manual_playtimes/#{entry.id}", params: { data: { minutes: 1 } }, headers: auth_headers_for(other),
        as: :json
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/manual_playtimes/#{entry.id}", headers: auth_headers_for(other)
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/manual_playtimes/#{entry.id}", headers: auth_headers_for(other, is_dev: true)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /users/:user_id/games/:game_id/playtime/mismatches" do
    let!(:entry) { create(:manual_playtime, user: member, game: game, platform: windows, minutes: 500) }

    before { steam_playtime(member, 600) }

    def settle(keep, platform: windows, as: member)
      post "#{playtime_path}/mismatches", params: { data: { platform_id: platform.platform_id, keep: keep } },
        headers: auth_headers_for(as), as: :json
    end

    it "keep mine stops the Provider's figure counting on that platform" do
      settle("manual")

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "total_minutes")).to eq(500)
      expect(json.dig("data", "mismatches")).to eq([])
      expect(json.dig("data", "breakdown", "provider_sets", 0, "counted")).to be(false)
      expect(entry.reload.keeps_over_provider).to eq("steam")
    end

    it "keep the Provider's deletes the Manual entry" do
      settle("provider")

      expect(json.dig("data", "total_minutes")).to eq(600)
      expect(json.dig("data", "mismatches")).to eq([])
      expect(UserGameManualPlaytime.exists?(entry.id)).to be(false)
    end

    it "is 422 when there is no mismatch on the platform, or for an unknown keep" do
      settle("sideways")
      expect(response).to have_http_status(:unprocessable_content)

      create(:manual_playtime, user: member, game: game, platform: switch, minutes: 5)
      settle("manual", platform: switch)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("no_mismatch")
    end

    it "is the member's own" do
      settle("provider", as: other)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameManualPlaytime.exists?(entry.id)).to be(true)
    end
  end
end

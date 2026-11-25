# frozen_string_literal: true

require "rails_helper"

# Playthroughs (spec api#457, ticket api#459; GLOSSARY.md "Playthrough"): one
# run of a game, measured as the Playtime gained since it started or a total
# set by hand. Writes are the member's own, or a Superadmin's (or the bot's)
# for anyone, and answer with the game's Playtime document. Ungated.
RSpec.describe "api/v1 playthroughs behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:other) { create(:user) }
  let(:game) { create(:game) }
  let!(:switch) { create(:platform, platform_name: "Nintendo Switch") }

  def playtime_path(user = member) = "/api/v1/users/#{user.user_id}/games/#{game.game_id}/playtime"
  def start_path(user = member) = "/api/v1/users/#{user.user_id}/games/#{game.game_id}/playthroughs"

  def add_time(minutes, platform: switch, mode: "add")
    post "/api/v1/users/#{member.user_id}/games/#{game.game_id}/manual_playtimes",
      params: { data: { platform_id: platform&.platform_id, minutes: minutes, mode: mode } },
      headers: auth_headers_for(member), as: :json
  end

  def start(as: member, user: member)
    post start_path(user), headers: auth_headers_for(as), as: :json
  end

  def playtime
    get playtime_path, headers: auth_headers_for(other)
    json.fetch("data")
  end

  describe "POST /users/:user_id/games/:game_id/playthroughs" do
    it "starts from zero, then measures the Playtime gained since, Manual Playtime included" do
      add_time(600)

      travel_to(Time.zone.parse("2026-11-20 12:00")) { start }

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "total_minutes")).to eq(600)
      expect(json.dig("data", "playthrough")).to include("minutes" => 0, "manual" => false,
        "started_at" => "2026-11-20T12:00:00.000Z")

      add_time(90)

      expect(json.dig("data", "playthrough", "minutes")).to eq(90)
      expect(playtime.dig("playthrough", "minutes")).to eq(90)
    end

    it "shows the Playtime it is counted from as baseline_minutes" do
      add_time(600)
      start
      add_time(90)

      expect(playtime.fetch("playthrough")).to include("baseline_minutes" => 600, "minutes" => 90)
    end

    it "never goes below zero when Playtime drops under the baseline" do
      add_time(600)
      start
      add_time(100, mode: "set")

      expect(playtime.dig("playthrough", "minutes")).to eq(0)
    end

    it "is refused while one is open, and allowed again once it has ended" do
      start
      start

      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("playthrough_open")
      expect(UserGamePlaythrough.count).to eq(1)

      post "/api/v1/playthroughs/#{UserGamePlaythrough.last.id}/abandon", headers: auth_headers_for(member)
      start
      expect(response).to have_http_status(:created)
    end

    it "is null with no earlier ones when the member has never started one" do
      expect(playtime).to include("playthrough" => nil, "playthroughs" => [])
    end

    it "is the member's own: another member is refused, a Superadmin and the bot may start one for anyone" do
      start(as: other)
      expect(response).to have_http_status(:forbidden)

      start(as: create(:user), user: other)
      expect(response).to have_http_status(:forbidden)

      post start_path(other), headers: auth_headers_for(member, is_dev: true), as: :json
      expect(response).to have_http_status(:created)

      post start_path, headers: service_headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it "is 404 for an unknown member or game" do
      post "/api/v1/users/#{member.user_id}/games/0/playthroughs", headers: service_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /playthroughs/:id" do
    let!(:playthrough) { create(:playthrough, user: member, game: game) }

    def set_total(total, as: member)
      patch "/api/v1/playthroughs/#{playthrough.id}", params: { data: { total_minutes: total } },
        headers: auth_headers_for(as), as: :json
    end

    it "sets a total by hand that overrides the measured time, and null goes back to measuring" do
      add_time(30)
      set_total(2700)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "playthrough")).to include("minutes" => 2700, "manual" => true)

      add_time(60)
      expect(json.dig("data", "playthrough", "minutes")).to eq(2700)

      set_total(nil)
      expect(json.dig("data", "playthrough")).to include("minutes" => 90, "manual" => false)
    end

    it "refuses a total that isn't a whole number of 0 or more, or is missing" do
      [ -1, 1.5, "x", 6_000_001, 10**12 ].each do |total|
        set_total(total)
        expect(response).to have_http_status(:unprocessable_content), total.inspect
        expect(json["error"]).to eq("invalid_total_minutes")
      end

      patch "/api/v1/playthroughs/#{playthrough.id}", params: { data: { minutes: 10 } },
        headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "takes up to 100,000 hours" do
      set_total(6_000_000)

      expect(response).to have_http_status(:ok)
    end

    it "refuses an ended one" do
      playthrough.update!(ended_at: Time.current, end_reason: "abandoned", final_minutes: 0)
      set_total(10)

      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("playthrough_closed")
    end

    it "is the member's own, or a Superadmin's" do
      set_total(10, as: other)
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/playthroughs/#{playthrough.id}", params: { data: { total_minutes: 10 } },
        headers: auth_headers_for(other, is_dev: true), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /playthroughs/:id/abandon" do
    it "ends it with the time it had, and lists it among the earlier ones" do
      add_time(60)
      travel_to(Time.zone.parse("2026-11-20 12:00")) { start }
      add_time(45)
      id = json.dig("data", "playthrough", "id")

      travel_to(Time.zone.parse("2026-11-22 18:00")) do
        post "/api/v1/playthroughs/#{id}/abandon", headers: auth_headers_for(member)
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "playthrough")).to be_nil
      expect(json.dig("data", "playthroughs")).to eq([ {
        "id" => id, "started_at" => "2026-11-20T12:00:00.000Z", "ended_at" => "2026-11-22T18:00:00.000Z",
        "end_reason" => "abandoned", "minutes" => 45, "manual" => false, "completion_id" => nil
      } ])

      add_time(500)
      expect(json.dig("data", "playthroughs", 0, "minutes")).to eq(45)
    end

    it "refuses an ended one and another member" do
      playthrough = create(:playthrough, user: member, game: game)

      post "/api/v1/playthroughs/#{playthrough.id}/abandon", headers: auth_headers_for(other)
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/playthroughs/#{playthrough.id}/abandon", headers: auth_headers_for(member)
      post "/api/v1/playthroughs/#{playthrough.id}/abandon", headers: auth_headers_for(member)
      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("playthrough_closed")
    end
  end

  describe "Now Playing" do
    def add_to_now_playing
      post "/api/v1/users/#{member.user_id}/now_playing", params: { data: { gamedb_game_id: game.game_id } },
        headers: auth_headers_for(member), as: :json
    end

    it "opens a Playthrough when the game goes on Now Playing, measured from then" do
      add_time(300)
      add_to_now_playing

      expect(response).to have_http_status(:created)
      expect(playtime.fetch("playthrough")).to include("minutes" => 0, "manual" => false)
      add_time(20)
      expect(playtime.dig("playthrough", "minutes")).to eq(20)
    end

    it "keeps the open one when there is one already" do
      open = create(:playthrough, user: member, game: game, manual_total_minutes: 600)
      add_to_now_playing

      expect(response).to have_http_status(:created)
      expect(playtime.fetch("playthrough")).to include("id" => open.id, "minutes" => 600)
      expect(UserGamePlaythrough.count).to eq(1)
    end

    it "leaves it open when the game comes off Now Playing" do
      add_to_now_playing
      delete "/api/v1/now_playing/#{json.dig('data', 'entry_id')}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(playtime.fetch("playthrough")).to be_present
    end
  end

  describe "Game Completion" do
    def complete(**data)
      post "/api/v1/users/#{member.user_id}/completions",
        params: { data: { gamedb_game_id: game.game_id, completion_type: "Main Story", **data } },
        headers: auth_headers_for(member), as: :json
    end

    it "closes the open Playthrough with the Completion and fills an empty final playtime from it" do
      add_time(1000)
      start
      add_time(200)

      complete

      expect(response).to have_http_status(:created)
      completion_id = json.dig("data", "completion_id")
      expect(json.dig("data", "final_playtime_hrs").to_d).to eq(BigDecimal("3.33"))
      expect(playtime).to include("playthrough" => nil)
      expect(playtime.fetch("playthroughs")).to contain_exactly(include(
        "end_reason" => "completed", "completion_id" => completion_id, "minutes" => 200
      ))
    end

    it "takes a set total, and keeps a final playtime the member sends" do
      create(:playthrough, user: member, game: game, manual_total_minutes: 2700)

      complete(final_playtime_hrs: 40)

      expect(json.dig("data", "final_playtime_hrs").to_d).to eq(40)
      expect(playtime.dig("playthroughs", 0)).to include("end_reason" => "completed", "minutes" => 2700)
    end

    it "fills nothing when no Playthrough is open" do
      create(:playthrough, user: member, game: game, ended_at: 1.day.ago, end_reason: "abandoned", final_minutes: 90)

      complete

      expect(json.dig("data", "final_playtime_hrs")).to be_nil
      expect(UserGamePlaythrough.where(end_reason: "completed")).to be_empty
    end

    it "leaves another game's Playthrough open" do
      other_game = create(:game)
      open = create(:playthrough, user: member, game: other_game)

      complete

      expect(open.reload.ended_at).to be_nil
    end
  end
end

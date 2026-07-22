# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the front-page dashboard: the most recent GOTM and
# NR-GOTM entries (round desc, game_index asc), each with its embedded game,
# capped per-list by the clamped `limit` param.
RSpec.describe "api/v1/dashboards behavior", type: :request do
  # Random very-high round numbers so these entries sort ahead of anything
  # else in the table (and concurrent rspec processes can't collide on the
  # (round_number, game_index) unique indexes).
  def fresh_round
    900_000 + SecureRandom.random_number(90_000)
  end

  describe "GET /api/v1/dashboard" do
    it "returns recent GOTM and NR-GOTM entries with embedded games, newest round first" do
      game = create(:game)
      round = fresh_round
      older_gotm = GotmEntry.create!(round_number: round, month_year: "January 2026", game_index: 1,
        gamedb_game_id: game.game_id)
      newer_gotm = GotmEntry.create!(round_number: round + 1, month_year: "February 2026", game_index: 1,
        gamedb_game_id: game.game_id)
      nr_round = fresh_round
      nr_entry = NrGotmEntry.create!(round_number: nr_round, month_year: "February 2026", game_index: 1,
        gamedb_game_id: game.game_id)

      get "/api/v1/dashboard", params: { limit: 20 }, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      gotm = json.dig("data", "gotm")
      newer_row = gotm.find { |e| e.fetch("gotm_id") == newer_gotm.gotm_id }
      older_row = gotm.find { |e| e.fetch("gotm_id") == older_gotm.gotm_id }
      expect(newer_row).to include(
        "round_number" => round + 1,
        "month_year" => "February 2026",
        "game_index" => 1,
        "gamedb_game_id" => game.game_id
      )
      expect(newer_row.fetch("game")).to include("game_id" => game.game_id, "title" => game.title)
      expect(gotm.index(newer_row)).to be < gotm.index(older_row)

      nr_row = json.dig("data", "nr_gotm").find { |e| e.fetch("nr_gotm_id") == nr_entry.nr_gotm_id }
      expect(nr_row).to include("round_number" => nr_round, "gamedb_game_id" => game.game_id)
      expect(nr_row.fetch("game")).to include("game_id" => game.game_id)

      expect(json.fetch("meta")).to eq("limit" => 20)
    end

    it "orders entries within a round by game_index ascending" do
      game = create(:game)
      round = fresh_round
      second = GotmEntry.create!(round_number: round, month_year: "March 2026", game_index: 2,
        gamedb_game_id: game.game_id)
      first = GotmEntry.create!(round_number: round, month_year: "March 2026", game_index: 1,
        gamedb_game_id: game.game_id)

      get "/api/v1/dashboard", params: { limit: 20 }, headers: service_headers

      ids = json.dig("data", "gotm").map { |e| e.fetch("gotm_id") }
      expect(ids.index(first.gotm_id)).to be < ids.index(second.gotm_id)
    end

    it "defaults the per-list limit to 10" do
      get "/api/v1/dashboard", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("meta")).to eq("limit" => 10)
    end

    it "caps each list at the clamped limit" do
      game = create(:game)
      round = fresh_round
      GotmEntry.create!(round_number: round, month_year: "April 2026", game_index: 1,
        gamedb_game_id: game.game_id)
      GotmEntry.create!(round_number: round, month_year: "April 2026", game_index: 2,
        gamedb_game_id: game.game_id)

      get "/api/v1/dashboard", params: { limit: 1 }, headers: service_headers

      expect(json.dig("data", "gotm").length).to eq(1)
      expect(json.fetch("meta")).to eq("limit" => 1)
    end

    it "clamps limit to the maximum of 20" do
      get "/api/v1/dashboard", params: { limit: 100 }, headers: service_headers

      expect(json.fetch("meta")).to eq("limit" => 20)
    end

    it "requires authentication" do
      get "/api/v1/dashboard"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

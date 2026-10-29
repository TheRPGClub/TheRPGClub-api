# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the GOTM round history: GOTM and NR-GOTM entries grouped
# and paged by round (the bot's `/gotm history` and `/gotm current`).
RSpec.describe "api/v1/gotm_rounds behavior", type: :request do
  let(:headers) { auth_headers_for(create(:user)) }

  def round_numbers
    json.fetch("data").map { |round| round.fetch("round_number") }
  end

  describe "GET /api/v1/gotm_rounds" do
    it "groups a round's GOTM and NR-GOTM games under one round" do
      gotm_a = create(:gotm_entry, round_number: 7, month_year: "March 2024", game_index: 0,
        reddit_url: "https://reddit.example/7", voting_results_message_id: "555")
      gotm_b = create(:gotm_entry, round_number: 7, month_year: "March 2024", game_index: 1)
      nr = create(:nr_gotm_entry, round_number: 7, month_year: "March 2024", game_index: 0)

      get "/api/v1/gotm_rounds", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      round = json.fetch("data").first
      expect(round.fetch("round_number")).to eq(7)
      expect(round.fetch("gotm")).to include("month_year" => "March 2024", "voting_results_message_id" => "555")
      expect(round.dig("gotm", "games").map { |g| g.fetch("gamedb_game_id") })
        .to eq([ gotm_a.gamedb_game_id, gotm_b.gamedb_game_id ])
      expect(round.dig("gotm", "games", 0)).to include(
        "game_index" => 0, "reddit_url" => "https://reddit.example/7", "thread_id" => nil
      )
      expect(round.dig("gotm", "games", 0, "game")).to include("game_id" => gotm_a.gamedb_game_id, "title" => gotm_a.game.title)
      expect(round.dig("nr_gotm", "games").map { |g| g.fetch("gamedb_game_id") }).to eq([ nr.gamedb_game_id ])
    end

    it "gives each game its newest linked thread and preloads images and platforms" do
      entry = create(:gotm_entry, round_number: 3)
      older = create(:discord_thread, created_at: 2.days.ago)
      newer = create(:discord_thread, created_at: 1.day.ago)
      create(:thread_game_link, thread: older, game: entry.game)
      create(:thread_game_link, thread: newer, game: entry.game)
      create(:game_platform, game: entry.game, platform: create(:platform, platform_name: "Alpha Deck"))

      get "/api/v1/gotm_rounds", headers: headers

      game = json.dig("data", 0, "gotm", "games", 0)
      expect(game.fetch("thread_id")).to eq(newer.thread_id)
      expect(game.dig("game", "platforms").map { |p| p.fetch("platform_name") }).to eq([ "Alpha Deck" ])
    end

    it "returns null for a kind with no entries in the round" do
      create(:gotm_entry, round_number: 4)

      get "/api/v1/gotm_rounds", headers: headers

      expect(json.dig("data", 0, "nr_gotm")).to be_nil
    end

    it "filters by kind" do
      create(:gotm_entry, round_number: 1)
      create(:nr_gotm_entry, round_number: 1)
      create(:nr_gotm_entry, round_number: 2)

      get "/api/v1/gotm_rounds", params: { kind: "gotm" }, headers: headers
      expect(round_numbers).to eq([ 1 ])
      expect(json.dig("data", 0, "nr_gotm")).to be_nil

      get "/api/v1/gotm_rounds", params: { kind: "nr_gotm" }, headers: headers
      expect(round_numbers).to eq([ 2, 1 ])
      expect(json.dig("data", 0, "gotm")).to be_nil

      get "/api/v1/gotm_rounds", params: { kind: "both" }, headers: headers
      expect(round_numbers).to eq([ 2, 1 ])
    end

    %w[gotm nr_gotm].each do |kind|
      it "counts and pages rounds, not entries, with kind=#{kind} and co-winners" do
        (1..4).each do |number|
          create(:"#{kind}_entry", round_number: number, game_index: 0)
          create(:"#{kind}_entry", round_number: number, game_index: 1)
        end

        get "/api/v1/gotm_rounds", params: { kind:, per: 2 }, headers: headers
        expect(json.fetch("meta")).to include("count" => 4, "pages" => 2)
        expect(round_numbers).to eq([ 4, 3 ])
        expect(json.dig("data", 0, kind, "games").length).to eq(2)

        get "/api/v1/gotm_rounds", params: { kind:, per: 2, page: 2 }, headers: headers
        expect(round_numbers).to eq([ 2, 1 ])
      end
    end

    it "filters by the trailing year of month_year" do
      create(:gotm_entry, round_number: 1, month_year: "December 2023")
      create(:gotm_entry, round_number: 2, month_year: "January 2024")
      create(:nr_gotm_entry, round_number: 3, month_year: "Feb 2024 ")

      get "/api/v1/gotm_rounds", params: { year: 2024 }, headers: headers

      expect(round_numbers).to eq([ 3, 2 ])
    end

    it "keeps a kind's whole round block when any of its game titles match q" do
      hit = create(:game, title: "Chrono Trigger")
      create(:gotm_entry, round_number: 1, game_index: 0, game: hit)
      sibling = create(:gotm_entry, round_number: 1, game_index: 1)
      create(:nr_gotm_entry, round_number: 1)
      create(:gotm_entry, round_number: 2)

      get "/api/v1/gotm_rounds", params: { q: "chrono" }, headers: headers

      expect(round_numbers).to eq([ 1 ])
      expect(json.dig("data", 0, "gotm", "games").map { |g| g.fetch("gamedb_game_id") })
        .to eq([ hit.game_id, sibling.gamedb_game_id ])
      expect(json.dig("data", 0, "nr_gotm")).to be_nil
    end

    it "sorts rounds descending by default and ascending with sort=asc" do
      [ 2, 9, 5 ].each { |number| create(:gotm_entry, round_number: number) }

      get "/api/v1/gotm_rounds", headers: headers
      expect(round_numbers).to eq([ 9, 5, 2 ])

      get "/api/v1/gotm_rounds", params: { sort: "asc" }, headers: headers
      expect(round_numbers).to eq([ 2, 5, 9 ])
    end

    it "pages by round, not by entry" do
      (1..3).each do |number|
        create(:gotm_entry, round_number: number, game_index: 0)
        create(:gotm_entry, round_number: number, game_index: 1)
        create(:nr_gotm_entry, round_number: number)
      end

      get "/api/v1/gotm_rounds", params: { per: 2, page: 2 }, headers: headers

      expect(round_numbers).to eq([ 1 ])
      expect(json.dig("data", 0, "gotm", "games").length).to eq(2)
      expect(json.fetch("meta")).to include("page" => 2, "pages" => 2, "count" => 3, "per" => 2, "prev" => 1, "next" => nil)
    end

    it "lists the years present for the selected kind, newest first, ignoring year and q" do
      create(:gotm_entry, round_number: 1, month_year: "May 2022")
      create(:gotm_entry, round_number: 2, month_year: "June 2024")
      create(:nr_gotm_entry, round_number: 3, month_year: "July 2025")
      create(:gotm_entry, round_number: 4, month_year: "Undated")

      get "/api/v1/gotm_rounds", params: { year: 2022, q: "zzz-no-match" }, headers: headers
      expect(json.fetch("data")).to eq([])
      expect(json.dig("meta", "years")).to eq([ 2025, 2024, 2022 ])

      get "/api/v1/gotm_rounds", params: { kind: "gotm" }, headers: headers
      expect(json.dig("meta", "years")).to eq([ 2024, 2022 ])
    end

    it "drops N/A placeholder NR-GOTM games but keeps the round" do
      placeholder = create(:game, title: " N/A ")
      create(:nr_gotm_entry, round_number: 1, game: placeholder, month_year: "May 2022")
      real = create(:nr_gotm_entry, round_number: 2, game_index: 0)
      create(:nr_gotm_entry, round_number: 2, game_index: 1, game: create(:game, title: "n/a"))

      get "/api/v1/gotm_rounds", headers: headers

      expect(round_numbers).to eq([ 2, 1 ])
      expect(json.dig("data", 0, "nr_gotm", "games").map { |g| g.fetch("gamedb_game_id") }).to eq([ real.gamedb_game_id ])
      expect(json.dig("data", 1, "nr_gotm")).to include("month_year" => "May 2022", "games" => [])
    end

    it "rejects an unknown kind, sort or a non-integer year" do
      get "/api/v1/gotm_rounds", params: { kind: "rpg" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("invalid_kind")

      get "/api/v1/gotm_rounds", params: { sort: "up" }, headers: headers
      expect(json.fetch("error")).to eq("invalid_sort")

      get "/api/v1/gotm_rounds", params: { year: "twenty" }, headers: headers
      expect(json.fetch("error")).to eq("invalid_year")
    end

    it "requires authentication" do
      get "/api/v1/gotm_rounds"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gotm_rounds/current" do
    it "returns the highest GOTM round with that round's NR-GOTM games" do
      create(:gotm_entry, round_number: 4)
      latest = create(:gotm_entry, round_number: 5, month_year: "May 2025")
      nr = create(:nr_gotm_entry, round_number: 5)
      create(:nr_gotm_entry, round_number: 6)

      get "/api/v1/gotm_rounds/current", headers: headers

      expect(response).to have_http_status(:ok)
      round = json.fetch("data")
      expect(round.fetch("round_number")).to eq(5)
      expect(round.dig("gotm", "month_year")).to eq("May 2025")
      expect(round.dig("gotm", "games", 0, "gamedb_game_id")).to eq(latest.gamedb_game_id)
      expect(round.dig("nr_gotm", "games").map { |g| g.fetch("gamedb_game_id") }).to eq([ nr.gamedb_game_id ])
    end

    it "returns no NR-GOTM block when the round has none, and drops N/A placeholders" do
      create(:gotm_entry, round_number: 8)
      create(:nr_gotm_entry, round_number: 7)

      get "/api/v1/gotm_rounds/current", headers: headers
      expect(json.dig("data", "nr_gotm")).to be_nil

      create(:nr_gotm_entry, round_number: 8, game: create(:game, title: "N/A"))
      get "/api/v1/gotm_rounds/current", headers: headers
      expect(json.dig("data", "nr_gotm", "games")).to eq([])
    end

    it "returns 404 when there are no GOTM rounds" do
      create(:nr_gotm_entry, round_number: 1)

      get "/api/v1/gotm_rounds/current", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end

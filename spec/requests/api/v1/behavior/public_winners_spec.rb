# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the unauthenticated recent-winners feed behind www's
# logged-out landing page: the latest 24 rounds' winning games, with no
# member data or Discord ids.
RSpec.describe "api/v1/public/winners behavior", type: :request do
  def items
    json.fetch("data")
  end

  describe "GET /api/v1/public/winners" do
    it "answers without authentication" do
      create(:gotm_entry, round_number: 1)

      get "/api/v1/public/winners"

      expect(response).to have_http_status(:ok)
      expect(json.fetch("meta")).to eq("rounds" => 1)
    end

    it "lists the winners newest round first, GOTM before NR-GOTM, game_index within a track" do
      old_gotm = create(:gotm_entry, round_number: 1, month_year: "January 2024")
      new_nr = create(:nr_gotm_entry, round_number: 2, month_year: "February 2024")
      new_gotm_b = create(:gotm_entry, round_number: 2, month_year: "February 2024", game_index: 1)
      new_gotm_a = create(:gotm_entry, round_number: 2, month_year: "February 2024", game_index: 0)

      get "/api/v1/public/winners"

      expect(items.map { |item| [ item.fetch("round_number"), item.fetch("kind"), item.fetch("game_id") ] }).to eq([
        [ 2, "gotm", new_gotm_a.gamedb_game_id ],
        [ 2, "gotm", new_gotm_b.gamedb_game_id ],
        [ 2, "nr_gotm", new_nr.gamedb_game_id ],
        [ 1, "gotm", old_gotm.gamedb_game_id ]
      ])
      expect(json.fetch("meta")).to eq("rounds" => 2)
    end

    it "carries only the public game fields" do
      entry = create(:gotm_entry, round_number: 3, month_year: "March 2024",
        reddit_url: "https://reddit.example/3", voting_results_message_id: "555")
      cover = create(:game_image, :primary, game: entry.game, kind: "cover")
      art = create(:game_image, :primary, game: entry.game, kind: "artwork")

      get "/api/v1/public/winners"

      expect(items.first).to eq(
        "round_number" => 3, "month_year" => "March 2024", "kind" => "gotm",
        "game_id" => entry.gamedb_game_id, "title" => entry.game.title,
        "cover_url" => cover.url, "art_url" => art.url
      )
      expect(response.body).not_to include("reddit", "555", "thread_id", "message_id", "user")
    end

    it "keeps only the latest 24 rounds" do
      (1..26).each do |number|
        create(:gotm_entry, round_number: number)
        create(:nr_gotm_entry, round_number: number)
      end

      get "/api/v1/public/winners"

      expect(items.map { |item| item.fetch("round_number") }.uniq).to eq((3..26).to_a.reverse)
      expect(items.length).to eq(48)
      expect(json.fetch("meta")).to eq("rounds" => 24)
    end

    it "drops the NR-GOTM N/A placeholders" do
      create(:nr_gotm_entry, round_number: 5, game: create(:game, title: " N/A "))
      gotm = create(:gotm_entry, round_number: 5)

      get "/api/v1/public/winners"

      expect(items.map { |item| item.fetch("game_id") }).to eq([ gotm.gamedb_game_id ])
    end

    it "is publicly cacheable for ten minutes" do
      create(:gotm_entry, round_number: 1)

      get "/api/v1/public/winners"

      expect(response.headers["Cache-Control"]).to include("public", "max-age=600")
    end

    it "serves the cached payload until a newer round busts it" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      first = create(:gotm_entry, round_number: 1)

      get "/api/v1/public/winners"
      first.game.update!(title: "Renamed")
      get "/api/v1/public/winners"
      expect(items.first.fetch("title")).not_to eq("Renamed")

      create(:gotm_entry, round_number: 2)
      get "/api/v1/public/winners"
      expect(items.map { |item| item.fetch("round_number") }).to eq([ 2, 1 ])
      expect(items.last.fetch("title")).to eq("Renamed")
    end

    it "returns an empty list when there are no rounds" do
      get "/api/v1/public/winners"

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => [], "meta" => { "rounds" => 0 })
    end
  end
end

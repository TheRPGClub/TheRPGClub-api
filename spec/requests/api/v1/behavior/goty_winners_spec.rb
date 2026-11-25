# frozen_string_literal: true

require "rails_helper"

# Where members see GOTY Vote winners (spec api#471, ticket api#476): the
# history of every year's winners, and a winning game's Awards on its page.
RSpec.describe "GOTY Vote winners behavior", type: :request do
  let(:member) { create(:user) }

  describe "GET /api/v1/goty_votes" do
    it "lists each decided year's winners in Award order, and none for an undecided year" do
      gotm, nr, goty, early = create_list(:game, 4)
      create(:goty_vote, year: 2025, decided_at: Time.utc(2026, 1, 19))
      create(:goty_winner, year: 2025, award: "game_of_the_year", game: goty, decided_by: "admin")
      create(:goty_winner, year: 2025, award: "gotm", game: gotm, decided_by: "vote")
      create(:goty_winner, year: 2025, award: "nr_gotm", game: nr, decided_by: "uncontested")
      # 2026 is in its runoff: one Award is already won, but the year is undecided.
      create(:goty_vote, year: 2026)
      create(:goty_winner, year: 2026, award: "gotm", game: early, decided_by: "vote")

      get "/api/v1/goty_votes", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      years = json.fetch("data")
      expect(years.map { |vote| vote["year"] }).to eq([ 2026, 2025 ])
      expect(years[0]["winners"]).to eq([])
      expect(years[1]["winners"].map { |winner| winner.values_at("award", "name", "gamedb_game_id", "decided_by") })
        .to eq([
          [ "gotm", "GOTM of the Year", gotm.game_id, "vote" ],
          [ "nr_gotm", "NR-GOTM of the Year", nr.game_id, "uncontested" ],
          [ "game_of_the_year", "Game of the Year", goty.game_id, "admin" ]
        ])
      expect(years[1]["winners"].first["game"]).to include("game_id" => gotm.game_id, "title" => gotm.title)
    end
  end

  describe "GET /api/v1/games/:id" do
    it "lists every Award the game won, newest year first" do
      game = create(:game)
      create(:goty_vote, year: 2024, decided_at: Time.utc(2025, 1, 19))
      create(:goty_vote, year: 2025, decided_at: Time.utc(2026, 1, 19))
      create(:goty_winner, year: 2024, award: "game_of_the_year", game: game)
      create(:goty_winner, year: 2025, award: "game_of_the_year", game: game)
      create(:goty_winner, year: 2025, award: "gotm", game: game)

      get "/api/v1/games/#{game.game_id}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "goty_awards")).to eq([
        { "year" => 2025, "award" => "gotm" },
        { "year" => 2025, "award" => "game_of_the_year" },
        { "year" => 2024, "award" => "game_of_the_year" }
      ])
    end

    it "lists no Awards for a game that won none, or only in an undecided year" do
      game = create(:game)
      create(:goty_vote, year: 2026)
      create(:goty_winner, year: 2026, award: "gotm", game: game)

      get "/api/v1/games/#{game.game_id}", headers: auth_headers_for(member)

      expect(json.dig("data", "goty_awards")).to eq([])
    end

    it "leaves goty_awards out for a member who cannot use the GOTY Vote Feature" do
      game = create(:game)
      set_feature_flag("goty_vote", "preview")

      get "/api/v1/games/#{game.game_id}", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).not_to have_key("goty_awards")
    end
  end
end

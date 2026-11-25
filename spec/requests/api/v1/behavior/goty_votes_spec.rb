# frozen_string_literal: true

require "rails_helper"

# The GOTY Vote reads (spec api#471, ticket api#472): each year's vote with
# its derived phase and dates, the live GOTM / NR-GOTM of the Year ballots,
# and a game's Game of the Year eligibility.
RSpec.describe "api/v1/goty_votes behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:base) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }

  describe "GET /api/v1/goty_votes" do
    it "lists every year newest first with its phase" do
      create(:goty_vote, year: 2026)
      create(:goty_vote, year: 2025, decided_at: Time.utc(2026, 1, 20))

      travel_to(Time.utc(2027, 1, 5)) { get "/api/v1/goty_votes", headers: auth_headers_for(member) }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |vote| vote.values_at("year", "phase") }).to eq([
        [ 2026, "nominating" ], [ 2025, "decided" ]
      ])
    end
  end

  describe "GET /api/v1/goty_votes/:year" do
    it "returns the phase, the default dates and the three Awards with the live ballots" do
      gotm_a, gotm_b, nr = create_list(:game, 3)
      create(:gotm_entry, round_number: base, month_year: "March 2026", game_index: 0, game: gotm_a)
      create(:gotm_entry, round_number: base, month_year: "March 2026", game_index: 1, game: gotm_b)
      create(:gotm_entry, round_number: base + 1, month_year: "April 2026", game: gotm_a)
      create(:nr_gotm_entry, round_number: base, month_year: "March 2026", game: nr)
      create(:goty_vote, year: 2026)

      travel_to(Time.utc(2026, 12, 15)) { get "/api/v1/goty_votes/2026", headers: auth_headers_for(member) }

      expect(response).to have_http_status(:ok)
      data = json.fetch("data")
      expect(data).to include("year" => 2026, "name" => "GOTY Vote 2026", "phase" => "upcoming",
        "nominations_open" => false, "voting_open" => false, "runoff_open" => false, "decided_at" => nil)
      expect(Time.zone.parse(data["nominations_open_at"])).to eq(Time.utc(2027, 1, 1, 5))
      expect(Time.zone.parse(data["voting_opens_at"])).to eq(Time.utc(2027, 1, 15, 17))
      expect(Time.zone.parse(data["voting_closes_at"])).to be_within(1.second).of(Time.utc(2027, 1, 18, 4, 59, 59))

      awards = data.fetch("awards")
      expect(awards.map { |award| award.values_at("award", "name") }).to eq([
        [ "gotm", "GOTM of the Year" ], [ "nr_gotm", "NR-GOTM of the Year" ], [ "game_of_the_year", "Game of the Year" ]
      ])
      expect(awards[0]["ballot"].map { |game| game["game_id"] }).to eq([ gotm_a.game_id, gotm_b.game_id ])
      expect(awards[0]["ballot"].first).to include("title" => gotm_a.title)
      expect(awards[1]["ballot"].map { |game| game["game_id"] }).to eq([ nr.game_id ])
      expect(awards[2]["ballot"]).to eq([])
    end

    it "is not found for a year with no GOTY Vote" do
      get "/api/v1/goty_votes/1999", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end

    it "is not found for a member while the Feature is in Preview" do
      create(:goty_vote, year: 2026)
      set_feature_flag("goty_vote", "preview")

      get "/api/v1/goty_votes/2026", headers: auth_headers_for(member)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/goty_votes/2026", headers: auth_headers_for(create(:user, role_admin: true))
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/games/:id/goty_eligibility" do
    let(:game) { create(:game) }

    it "says a game released in the year is eligible, with the date judged" do
      create(:release, game: game, release_date: Date.new(2026, 1, 1), date_precision: "year", source: "manual")

      get "/api/v1/games/#{game.game_id}/goty_eligibility", params: { year: 2026 }, headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "game_id" => game.game_id, "year" => 2026, "eligible" => true, "reason" => nil,
        "released_on" => "2026-01-01", "date_precision" => "year", "source" => "release"
      )
    end

    it "gives the reason a game is not eligible" do
      get "/api/v1/games/#{game.game_id}/goty_eligibility", params: { year: 2026 }, headers: auth_headers_for(member)

      expect(json.fetch("data")).to include("eligible" => false, "reason" => "release_unknown", "released_on" => nil)
    end

    it "is a bad request without a year" do
      get "/api/v1/games/#{game.game_id}/goty_eligibility", headers: auth_headers_for(member)

      expect(response).to have_http_status(:bad_request)
    end

    it "is not found for an unknown game" do
      get "/api/v1/games/0/goty_eligibility", params: { year: 2026 }, headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end
  end
end

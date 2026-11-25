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

    it "says where each GOTM / NR-GOTM of the Year game won, before and after the freeze" do
      twice, once, nr, nominated = create_list(:game, 4)
      create(:gotm_entry, round_number: base, month_year: "January 2026", game_index: 0, game: twice)
      create(:gotm_entry, round_number: base, month_year: "January 2026", game_index: 1, game: once)
      create(:gotm_entry, round_number: base + 2, month_year: "March 2026", game: twice)
      create(:nr_gotm_entry, round_number: base + 1, month_year: "February 2026", game: nr)
      vote = create(:goty_vote, year: 2026)
      create(:goty_nomination, year: 2026, game: nominated)
      won = lambda do |award|
        award["ballot"].to_h { |game| [ game["game_id"], game["won_in"] ] }
      end
      expected_gotm = {
        twice.game_id => [ { "round_number" => base, "month_year" => "January 2026" },
                           { "round_number" => base + 2, "month_year" => "March 2026" } ],
        once.game_id => [ { "round_number" => base, "month_year" => "January 2026" } ]
      }

      travel_to(Time.utc(2027, 1, 5)) { get "/api/v1/goty_votes/2026", headers: auth_headers_for(member) }
      awards = json.dig("data", "awards")
      expect(won.call(awards[0])).to eq(expected_gotm)
      expect(won.call(awards[1])).to eq(nr.game_id => [ { "round_number" => base + 1, "month_year" => "February 2026" } ])
      expect(awards[2]["ballot"].map { |game| game["game_id"] }).to eq([ nominated.game_id ])
      expect(awards[2]["ballot"].first).not_to have_key("won_in")

      nominated.update!(initial_release_date: Date.new(2026, 6, 1))
      Goty::FreezeCandidates.call(vote, now: vote.voting_opens_at)
      travel_to(vote.voting_opens_at + 1.hour) { get "/api/v1/goty_votes/2026", headers: auth_headers_for(member) }
      awards = json.dig("data", "awards")
      expect(won.call(awards[0])).to eq(expected_gotm)
      expect(awards[2]["ballot"].first).not_to have_key("won_in")
    end

    it "loads where the games won in a fixed number of queries" do
      create(:goty_vote, year: 2026)
      count = lambda do
        queries = 0
        callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          travel_to(Time.utc(2027, 1, 5)) { get "/api/v1/goty_votes/2026", headers: auth_headers_for(member) }
        end
        queries
      end
      create(:gotm_entry, round_number: base, month_year: "January 2026", game: create(:game))
      count.call
      one = count.call

      create_list(:game, 4).each_with_index do |game, index|
        create(:gotm_entry, round_number: base + 1 + index, month_year: "May 2026", game: game)
        create(:nr_gotm_entry, round_number: base + 1 + index, month_year: "May 2026", game: game)
      end

      expect(count.call).to eq(one)
      expect(json.dig("data", "awards", 0, "ballot").size).to eq(5)
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

  describe "GET /api/v1/games/goty_eligibility" do
    let(:in_year) { create(:game) }
    let(:last_year) { create(:game) }
    let(:unknown) { create(:game) }

    before do
      create(:release, game: in_year, release_date: Date.new(2026, 1, 1), date_precision: "year", source: "manual")
      create(:release, game: last_year, release_date: Date.new(2025, 6, 3), date_precision: "day", source: "igdb")
    end

    def batch(params)
      get "/api/v1/games/goty_eligibility", params: params, headers: auth_headers_for(member)
    end

    it "answers for every game in the order given, as the single endpoint does" do
      ids = [ unknown, in_year, last_year ].map(&:game_id)
      batch(year: 2026, game_ids: ids.join(","))

      expect(response).to have_http_status(:ok)
      singles = ids.map do |id|
        get "/api/v1/games/#{id}/goty_eligibility", params: { year: 2026 }, headers: auth_headers_for(member)
        json.fetch("data")
      end
      batch(year: 2026, game_ids: ids.join(","))
      expect(json.fetch("data")).to eq(singles)
      expect(json.fetch("data").map { |item| item.values_at("game_id", "eligible", "reason", "released_on") }).to eq([
        [ unknown.game_id, false, "release_unknown", nil ],
        [ in_year.game_id, true, nil, "2026-01-01" ],
        [ last_year.game_id, false, "not_released_in_year", "2025-06-03" ]
      ])
    end

    it "leaves out unknown ids and answers a repeated id once" do
      batch(year: 2026, game_ids: "0,#{in_year.game_id},#{in_year.game_id}")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |item| item["game_id"] }).to eq([ in_year.game_id ])
    end

    it "is a bad request without a valid year" do
      batch(game_ids: in_year.game_id.to_s)
      expect(response).to have_http_status(:bad_request)

      batch(year: "soon", game_ids: in_year.game_id.to_s)
      expect(response).to have_http_status(:bad_request)
    end

    it "is a bad request without game_ids" do
      batch(year: 2026)
      expect(response).to have_http_status(:bad_request)

      batch(year: 2026, game_ids: "")
      expect(response).to have_http_status(:bad_request)
    end

    it "refuses ids that are not whole numbers" do
      batch(year: 2026, game_ids: "#{in_year.game_id},abc")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_game_ids")
    end

    it "refuses more than 50 ids" do
      batch(year: 2026, game_ids: (1..51).to_a.join(","))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("too_many_game_ids")
    end

    it "answers in a fixed number of queries" do
      count_queries = lambda do |games|
        Features.forget_cached_states!
        queries = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          queries += 1 unless payload[:name] == "SCHEMA"
        end
        begin
          batch(year: 2026, game_ids: games.map(&:game_id).join(","))
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        queries
      end

      count_queries.call([ in_year ]) # warm the per-process caches
      small = count_queries.call([ in_year, unknown ])
      many = [ in_year, last_year, unknown ] + create_list(:game, 5).each do |game|
        create(:release, game: game, release_date: Date.new(2026, 3, 1), date_precision: "day", source: "igdb")
      end
      large = count_queries.call(many)

      expect(json.fetch("data").size).to eq(8)
      expect(large).to eq(small)
    end
  end
end

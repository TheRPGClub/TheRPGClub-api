# frozen_string_literal: true

require "rails_helper"

# Award voting over HTTP (spec api#471, ticket api#474): casting, the admin
# date moves and tie pick, and each Award's standings on the GOTY Vote. The
# voting rules themselves are specified in spec/services/goty/*.
RSpec.describe "api/v1/goty_votes award voting behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:admin) { create(:user, role_admin: true) }
  let!(:vote) { create(:goty_vote, year: 2026, candidates_frozen_at: Time.utc(2027, 1, 15, 17)) }
  let(:voting) { vote.voting_opens_at + 1.hour }
  let(:after_close) { vote.voting_closes_at + 1.minute }

  def candidates!(award, count)
    create_list(:game, count).each_with_index.map do |game, position|
      GotyCandidate.create!(year: 2026, award: award, gamedb_game_id: game.game_id, position: position)
      game.game_id
    end
  end

  def headers_for(principal)
    principal == :service ? service_headers : auth_headers_for(principal)
  end

  def cast(award, game_id, as: member, user_id: nil, at: voting)
    body = { data: { award: award, gamedb_game_id: game_id, user_id: user_id }.compact }
    travel_to(at) { post "/api/v1/goty_votes/2026/votes", params: body, headers: headers_for(as), as: :json }
  end

  def show(as: member, at: voting, **params)
    travel_to(at) { get "/api/v1/goty_votes/2026", params: params, headers: headers_for(as) }
    json.fetch("data")
  end

  def award(data, key)
    data.fetch("awards").find { |row| row["award"] == key }
  end

  describe "POST /goty_votes/:year/votes" do
    let(:games) { candidates!("gotm", 4) }

    it "casts, reports the cap, and toggles off" do
      cast("gotm", games[0])

      expect(response).to have_http_status(:created)
      data = json.fetch("data")
      expect(data).to include("action" => "voted", "cap" => 2, "runoff" => false, "removed_votes" => [],
        "warning" => nil)
      expect(data["vote"]).to include("year" => 2026, "award" => "gotm", "user_id" => member.user_id,
        "gamedb_game_id" => games[0], "runoff" => false)

      cast("gotm", games[0])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "action")).to eq("unvoted")
      expect(json.dig("data", "removed_votes", 0, "gamedb_game_id")).to eq(games[0])
    end

    it "evicts the oldest vote at the cap" do
      cast("gotm", games[0])
      cast("gotm", games[1], at: voting + 1.minute)
      cast("gotm", games[2], at: voting + 2.minutes)

      expect(json.dig("data", "removed_votes").map { |row| row["gamedb_game_id"] }).to eq([ games[0] ])
      expect(json.dig("data", "warning")).to match(/oldest vote/)
    end

    it "lets the service cast for a named member, and needs the member" do
      cast("gotm", games[0], as: :service, user_id: member.user_id)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "vote", "user_id")).to eq(member.user_id)

      cast("gotm", games[1], as: :service)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("user_id_required")
    end

    it "lets a member cast only for themselves" do
      cast("gotm", games[0], user_id: create(:user).user_id)

      expect(response).to have_http_status(:forbidden)
    end

    it "gives an error code for each refusal" do
      only = candidates!("nr_gotm", 1).first
      [
        [ [ "gotm", games[0], { at: vote.voting_opens_at - 1.minute } ], "voting_closed" ],
        [ [ "gotm", only, {} ], "not_a_candidate" ],
        [ [ "nr_gotm", only, {} ], "uncontested" ],
        [ [ "best_boss", games[0], {} ], "unknown_award" ]
      ].each do |(key, game_id, options), code|
        cast(key, game_id, **options)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to eq(code)
      end
    end

    it "refuses a game outside the runoff" do
      ties = { "gotm" => games.first(2).sort }
      vote.update!(closed_at: vote.voting_closes_at, pending_ties: ties, runoff_ties: ties,
        runoff_opens_at: vote.voting_closes_at, runoff_closes_at: vote.voting_closes_at + 1.day)

      cast("gotm", games[3], at: after_close)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("not_in_runoff")
    end
  end

  describe "GET /goty_votes/:year standings" do
    let!(:gotm) { candidates!("gotm", 3) }

    before do
      cast("gotm", gotm[1])
      cast("gotm", gotm[1], as: admin)
      cast("gotm", gotm[0], as: create(:user))
    end

    it "shows a member their own votes and cap, and hides the counts while voting is open" do
      data = award(show, "gotm")

      expect(data["ballot"].map { |game| game["game_id"] }).to eq(gotm)
      expect(data).to include("cap" => 1, "own_votes" => [ gotm[1] ], "own_runoff_votes" => [],
        "runoff_ballot" => [], "pending_tie" => [], "winner" => nil, "result" => nil)
      expect(data["tally"]).to eq("counts_hidden" => true, "runoff_counts_hidden" => true, "games" => [])
    end

    it "shows staff the anonymous tally while open, and another member's votes to the service" do
      tally = award(show(as: admin), "gotm")["tally"]

      expect(tally["counts_hidden"]).to be(false)
      expect(tally["games"]).to eq([
        { "gamedb_game_id" => gotm[0], "votes" => 1, "runoff_votes" => 0 },
        { "gamedb_game_id" => gotm[1], "votes" => 2, "runoff_votes" => 0 },
        { "gamedb_game_id" => gotm[2], "votes" => 0, "runoff_votes" => 0 }
      ])

      expect(award(show(as: :service, user_id: member.user_id), "gotm")["own_votes"]).to eq([ gotm[1] ])
    end

    it "shows everyone the full result and the winner once decided" do
      Goty::Decide.close!(vote, now: after_close)

      data = award(show(at: after_close + 1.minute), "gotm")

      expect(data["tally"]["counts_hidden"]).to be(false)
      expect(data["winner"]).to include("gamedb_game_id" => gotm[1], "decided_by" => "vote")
      expect(data.dig("winner", "game", "game_id")).to eq(gotm[1])
      row = data["result"].find { |game| game["gamedb_game_id"] == gotm[1] }
      expect(row["voters"].map { |user| user["user_id"] }).to contain_exactly(member.user_id, admin.user_id)
      expect(row["runoff_voters"]).to eq([])
    end
  end

  describe "PATCH /goty_votes/:year" do
    def patch_vote(attrs, as: admin, at: Time.utc(2026, 12, 15))
      travel_to(at) do
        patch "/api/v1/goty_votes/2026", params: { data: attrs }, headers: headers_for(as), as: :json
      end
    end

    it "moves the dates, keeping the weekend window when only the open moves" do
      patch_vote({ voting_opens_at: "2027-01-22T17:00:00Z" })

      expect(response).to have_http_status(:ok)
      expect(Time.zone.parse(json.dig("data", "voting_opens_at"))).to eq(Time.utc(2027, 1, 22, 17))
      expect(Time.zone.parse(json.dig("data", "voting_closes_at"))).to be_within(1.second)
        .of(Time.utc(2027, 1, 25, 4, 59, 59))
    end

    it "refuses dates out of order" do
      patch_vote({ nominations_open_at: "2027-01-20T00:00:00Z" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(vote.reload.nominations_open_at).to eq(Time.utc(2027, 1, 1, 5))
    end

    it "keeps the open once candidates are frozen, but lets the close move" do
      patch_vote({ voting_opens_at: "2027-01-16T17:00:00Z" }, at: voting)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("voting_opened")

      patch_vote({ voting_closes_at: voting.iso8601 }, at: voting)
      expect(response).to have_http_status(:ok)
    end

    it "is for admins, and not once decided" do
      patch_vote({ voting_opens_at: "2027-01-22T17:00:00Z" }, as: member)
      expect(response).to have_http_status(:forbidden)

      vote.update!(decided_at: after_close)
      patch_vote({ voting_closes_at: "2027-01-20T00:00:00Z" }, at: after_close)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("goty_vote_decided")
    end
  end

  describe "POST /goty_votes/:year/awards/:award/resolve_tie" do
    let(:goty) { candidates!("game_of_the_year", 3) }
    let(:path) { "/api/v1/goty_votes/2026/awards/game_of_the_year/resolve_tie" }

    before do
      ties = { "game_of_the_year" => goty.first(2).sort }
      vote.update!(closed_at: vote.voting_closes_at, pending_ties: ties, runoff_ties: ties,
        runoff_opens_at: vote.voting_closes_at, runoff_closes_at: vote.voting_closes_at + 1.day,
        runoff_closed_at: vote.voting_closes_at + 1.day)
    end

    def resolve(game_id, as: admin)
      at = vote.voting_closes_at + 2.days
      travel_to(at) do
        post path, params: { data: { gamedb_game_id: game_id } }, headers: headers_for(as), as: :json
      end
    end

    it "records the admin's pick and decides the GOTY Vote" do
      resolve(goty[1])

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "phase")).to eq("decided")
      expect(award(json["data"], "game_of_the_year")["winner"]).to include("gamedb_game_id" => goty[1],
        "decided_by" => "admin")
    end

    it "refuses a game that is not tied, an Award with no tie, and members" do
      resolve(goty[2])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_pick")

      travel_to(vote.voting_closes_at + 2.days) do
        post "/api/v1/goty_votes/2026/awards/gotm/resolve_tie", params: { data: { gamedb_game_id: goty[0] } },
          headers: auth_headers_for(admin), as: :json
      end
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("no_tie")

      resolve(goty[0], as: member)
      expect(response).to have_http_status(:forbidden)
    end
  end
end

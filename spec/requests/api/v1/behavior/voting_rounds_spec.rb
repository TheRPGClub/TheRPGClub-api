# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the round lifecycle endpoints: open reads with the derived
# phase, admin/service rescheduling and tie-breaking, and the bot's legacy
# writes (voting_info, gotm_entries) mirrored into voting_rounds.
RSpec.describe "api/v1/voting_rounds behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:admin) { create(:user, role_admin: true) }
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }
  let(:base) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }

  describe "GET /api/v1/voting_rounds/current" do
    it "returns the lowest undecided round with its phase and windows" do
      create(:voting_round, round_number: base, voting_opens_at: opens_at - 30.days, decided_at: opens_at - 25.days)
      create(:voting_round, round_number: base + 1, voting_opens_at: opens_at)

      travel_to(opens_at + 1.hour) { get "/api/v1/voting_rounds/current", headers: auth_headers_for(member) }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "round_number" => base + 1, "month_year" => "November 2026", "phase" => "voting",
        "nominations_open" => false, "voting_open" => true, "voting_ended" => false,
        "runoff_open" => false, "runoff_ended" => false, "runoff_opens_at" => nil, "runoff_closes_at" => nil,
        "pending_ties" => {}, "runoff_ties" => {}
      )
      expect(Time.zone.parse(json.dig("data", "voting_opens_at"))).to eq(opens_at)
    end

    it "embeds the tied games" do
      game = create(:game)
      create(:voting_round, round_number: base, voting_opens_at: opens_at, closed_at: opens_at + 3.days,
        pending_ties: { "gotm" => [ game.game_id ] })

      travel_to(opens_at + 4.days) { get "/api/v1/voting_rounds/current", headers: auth_headers_for(member) }

      expect(json.dig("data", "phase")).to eq("tie")
      expect(json.dig("data", "pending_ties", "gotm").sole).to include("game_id" => game.game_id, "title" => game.title)
    end

    it "exposes an open runoff with its window and ballot" do
      games = create_list(:game, 2)
      ties = { "gotm" => games.map(&:game_id).sort }
      closed_at = opens_at + 3.days
      create(:voting_round, round_number: base, voting_opens_at: opens_at, closed_at: closed_at,
        pending_ties: ties, runoff_ties: ties, runoff_opens_at: closed_at, runoff_closes_at: closed_at + 1.day)

      travel_to(closed_at + 1.hour) { get "/api/v1/voting_rounds/current", headers: auth_headers_for(member) }

      expect(json.fetch("data")).to include(
        "phase" => "runoff", "voting_open" => false, "voting_ended" => true,
        "runoff_open" => true, "runoff_ended" => false
      )
      expect(Time.zone.parse(json.dig("data", "runoff_closes_at"))).to eq(closed_at + 1.day)
      expect(json.dig("data", "runoff_ties", "gotm").map { |game| game.fetch("game_id") }).to eq(ties["gotm"])
      expect(json.dig("data", "pending_ties", "gotm").length).to eq(2)
    end

    it "404s when no round is scheduled" do
      get "/api/v1/voting_rounds/current", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/voting_rounds/current"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/voting_rounds" do
    it "lists rounds newest first" do
      create(:voting_round, round_number: base)
      create(:voting_round, round_number: base + 1)

      get "/api/v1/voting_rounds", headers: auth_headers_for(member)

      expect(json.fetch("data").map { |round| round.fetch("round_number") }.first(2)).to eq([ base + 1, base ])
    end
  end

  describe "PATCH /api/v1/voting_rounds/:id" do
    let!(:round) { create(:voting_round, round_number: base, voting_opens_at: opens_at) }

    it "lets an admin reschedule the vote, moving the default close with it" do
      patch "/api/v1/voting_rounds/#{base}", params: { data: { voting_opens_at: (opens_at + 7.days).iso8601 } },
        headers: auth_headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(round.reload.voting_closes_at).to be_within(1.second).of(Voting::Schedule.default_closes_at(opens_at + 7.days))
    end

    it "closes voting early when the close is moved to now" do
      travel_to(opens_at + 1.hour) do
        patch "/api/v1/voting_rounds/#{base}", params: { data: { voting_closes_at: Time.current.iso8601 } },
          headers: service_headers, as: :json
      end

      expect(json.dig("data", "phase")).to eq("closed")
    end

    it "refuses a decided round" do
      round.update!(decided_at: opens_at + 3.days)

      patch "/api/v1/voting_rounds/#{base}", params: { data: { month_year: "Whenever" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "round_decided")
    end

    it "is forbidden to members" do
      patch "/api/v1/voting_rounds/#{base}", params: { data: { month_year: "Whenever" } },
        headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/voting_rounds/:id/resolve_tie" do
    let(:games) { create_list(:game, 2) }

    before do
      create(:voting_round, round_number: base, voting_opens_at: opens_at, closed_at: opens_at + 3.days,
        pending_ties: { "gotm" => games.map(&:game_id).sort })
    end

    it "records the admin's pick and decides the round" do
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "gotm", gamedb_game_ids: [ games.first.game_id ] } },
        headers: auth_headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "phase")).to eq("decided")
      expect(GotmEntry.where(round_number: base).pluck(:gamedb_game_id)).to eq([ games.first.game_id ])
    end

    it "422s for a game outside the tie" do
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "gotm", gamedb_game_ids: [ create(:game).game_id ] } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_pick")
    end

    it "422s for a category with no tie" do
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "nr_gotm", gamedb_game_ids: [ games.first.game_id ] } },
        headers: service_headers, as: :json

      expect(json).to include("error" => "no_tie")
    end

    it "is forbidden to members" do
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "gotm", gamedb_game_ids: [ games.first.game_id ] } },
        headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  # While the bot still drives the lifecycle, its writes keep voting_rounds in
  # step (Voting::LegacySync); the mapping itself is covered in its own spec.
  describe "the bot's legacy writes" do
    it "schedules the next round when the wizard re-dates a decided round's voting_info row" do
      create(:gotm_entry, round_number: base)
      create(:voting_info, round_number: base, next_vote_at: opens_at - 30.days)

      patch "/api/v1/voting_info/#{base}", params: { data: { next_vote_at: opens_at.iso8601 } },
        headers: service_headers, as: :json

      expect(VotingRound.find(base + 1).voting_opens_at).to eq(opens_at)
    end

    it "decides the round when the wizard records its GOTM winner" do
      create(:voting_round, round_number: base, voting_opens_at: opens_at)

      post "/api/v1/gotm_entries",
        params: { data: { round_number: base, month_year: "November 2026", game_index: 0,
                          gamedb_game_id: create(:game).game_id } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(VotingRound.find(base).decided_at).to be_present
      expect(VotingRound.current.round_number).to eq(base + 1)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the GOTM / NR-GOTM vote endpoints (#173). Casting is
# owner-gated (service may act for anyone; admins get no exemption) and only
# allowed inside the round's voting window (next_vote_at until the deadline,
# defaulting to the end of the following Sunday, US Eastern). Identified vote
# rows stay admin/service-only until voting has ended; the anonymous tally is
# always open. Toggle / cap-eviction rules live in Voting::CastVote.
RSpec.describe "api/v1/votes behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Fixed timeline: voting opens Friday 2026-06-05 17:00 UTC, so the default
  # deadline is the end of Sunday 2026-06-07 US Eastern (2026-06-08 03:59 UTC).
  let(:opens_at) { Time.utc(2026, 6, 5, 17, 0, 0) }
  let(:member) { create(:user) }
  let(:round) { SecureRandom.random_number(1_000_000_000) }

  def schedule_voting!(round_number)
    create(:voting_info, round_number: round_number, next_vote_at: opens_at)
  end

  def before_voting(&) = travel_to(Time.utc(2026, 6, 4, 12), &)
  def during_voting(&) = travel_to(Time.utc(2026, 6, 6, 12), &)
  def after_voting(&) = travel_to(Time.utc(2026, 6, 9, 12), &)

  def cast_gotm(round_number, user, nomination, headers)
    post "/api/v1/gotm_entries/#{round_number}/votes",
      params: { data: { user_id: user.user_id, nomination_id: nomination.nomination_id } },
      headers: headers, as: :json
  end

  describe "POST /api/v1/gotm_entries/:round/votes" do
    it "casts a member's own vote while the window is open" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      during_voting do
        expect {
          cast_gotm(round, member, nomination, auth_headers_for(member))
        }.to change(GotmVote.where(round_number: round, user_id: member.user_id), :count).by(1)
      end

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "action")).to eq("voted")
      expect(json.dig("data", "vote")).to include(
        "round_number" => round,
        "user_id" => member.user_id,
        "nomination_id" => nomination.nomination_id,
        "gamedb_game_id" => nomination.gamedb_game_id
      )
      expect(json.dig("data", "removed_votes")).to eq([])
      expect(json.dig("data", "cap")).to eq(2)
      expect(json.dig("data", "warning")).to be_nil
    end

    it "toggles the vote off when the game was already voted (200, unvoted)" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      during_voting do
        cast_gotm(round, member, nomination, auth_headers_for(member))
        cast_gotm(round, member, nomination, auth_headers_for(member))
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "action")).to eq("unvoted")
      expect(json.dig("data", "vote")).to be_nil
      expect(json.dig("data", "removed_votes").length).to eq(1)
      expect(json.dig("data", "warning")).to be_present
      expect(GotmVote.where(round_number: round, user_id: member.user_id)).to be_empty
    end

    it "toggles off via a different nomination of the same game" do
      schedule_voting!(round)
      game = create(:game)
      first_nomination = create(:gotm_nomination, round_number: round, game: game)
      second_nomination = create(:gotm_nomination, round_number: round, game: game)

      during_voting do
        cast_gotm(round, member, first_nomination, auth_headers_for(member))
        cast_gotm(round, member, second_nomination, auth_headers_for(member))
      end

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "action")).to eq("unvoted")
      expect(GotmVote.where(round_number: round, user_id: member.user_id)).to be_empty
    end

    it "evicts the oldest vote when casting a new game at the cap" do
      schedule_voting!(round)
      nominations = create_list(:gotm_nomination, 3, round_number: round) # < 9 noms => cap 2

      during_voting do
        cast_gotm(round, member, nominations[0], auth_headers_for(member))
        cast_gotm(round, member, nominations[1], auth_headers_for(member))
        cast_gotm(round, member, nominations[2], auth_headers_for(member))
      end

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "action")).to eq("voted")
      expect(json.dig("data", "removed_votes").length).to eq(1)
      expect(json.dig("data", "removed_votes", 0, "gamedb_game_id")).to eq(nominations[0].gamedb_game_id)
      expect(json.dig("data", "warning")).to include("cap (2)")
      expect(GotmVote.where(round_number: round, user_id: member.user_id).pluck(:gamedb_game_id))
        .to contain_exactly(nominations[1].gamedb_game_id, nominations[2].gamedb_game_id)
    end

    it "rejects a cast before voting opens" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      before_voting { cast_gotm(round, member, nomination, auth_headers_for(member)) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "voting_closed")
      expect(GotmVote.where(round_number: round)).to be_empty
    end

    it "rejects a cast after the default Friday-to-Sunday deadline" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      after_voting { cast_gotm(round, member, nomination, auth_headers_for(member)) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "voting_closed")
    end

    it "rejects a cast for a round with no voting schedule — even from the service" do
      nomination = create(:gotm_nomination, round_number: round)

      cast_gotm(round, member, nomination, service_headers)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "voting_closed")
    end

    it "404s when the nomination belongs to a different round" do
      schedule_voting!(round)
      foreign_nomination = create(:gotm_nomination) # some other round

      during_voting { cast_gotm(round, member, foreign_nomination, auth_headers_for(member)) }

      expect(response).to have_http_status(:not_found)
      expect(json).to include("error" => "nomination_not_found")
    end

    it "422s when the nomination has no game attached" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round, game: nil)

      during_voting { cast_gotm(round, member, nomination, auth_headers_for(member)) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nomination_missing_game")
    end

    it "forbids a member casting for someone else" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      during_voting { cast_gotm(round, member, nomination, auth_headers_for(create(:user))) }

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "forbids even an admin casting for someone else (only the service may)" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      during_voting { cast_gotm(round, member, nomination, auth_headers_for(create(:user, :admin))) }

      expect(response).to have_http_status(:forbidden)
    end

    it "lets the service cast on behalf of any user" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)

      during_voting { cast_gotm(round, member, nomination, service_headers) }

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "vote", "user_id")).to eq(member.user_id)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/gotm_entries/#{round}/votes", params: { user_id: member.user_id },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/gotm_entries/#{round}/votes",
        params: { data: { user_id: member.user_id, nomination_id: 1 } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gotm_entries/:round/votes (identified list)" do
    it "serves admin/service the identified rows oldest first while voting is open" do
      schedule_voting!(round)
      nomination = create(:gotm_nomination, round_number: round)
      newer = create(:gotm_vote, nomination: nomination, voted_at: 1.hour.ago)
      older = create(:gotm_vote, round_number: round, voted_at: 2.hours.ago)

      during_voting { get "/api/v1/gotm_entries/#{round}/votes", headers: service_headers }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |v| v.fetch("vote_id") }).to eq([ older.vote_id, newer.vote_id ])
      expect(json.fetch("data").first).to include("user_id" => older.user_id, "round_number" => round)
      expect(json.dig("data", 0, "user")).to include("user_id" => older.user_id)
      expect(json.fetch("meta")).to include("count" => 2)
    end

    it "hides identified rows from regular users while voting is open" do
      schedule_voting!(round)
      create(:gotm_vote, round_number: round)

      during_voting { get "/api/v1/gotm_entries/#{round}/votes", headers: auth_headers_for(member) }

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "opens identified rows to any authenticated caller once voting has ended" do
      schedule_voting!(round)
      vote = create(:gotm_vote, round_number: round)

      after_voting { get "/api/v1/gotm_entries/#{round}/votes", headers: auth_headers_for(member) }

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").first).to include("vote_id" => vote.vote_id, "user_id" => vote.user_id)
    end

    it "requires authentication" do
      get "/api/v1/gotm_entries/#{round}/votes"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gotm_entries/:round/votes/tally" do
    it "serves anonymous per-nomination counts to any member, most-voted first" do
      popular = create(:gotm_nomination, round_number: round)
      niche = create(:gotm_nomination, round_number: round)
      create(:gotm_nomination, round_number: round) # zero votes: no tally row
      create_list(:gotm_vote, 2, nomination: popular)
      create(:gotm_vote, nomination: niche)

      get "/api/v1/gotm_entries/#{round}/votes/tally", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        { "nomination_id" => popular.nomination_id, "gamedb_game_id" => popular.gamedb_game_id,
          "vote_count" => 2 },
        { "nomination_id" => niche.nomination_id, "gamedb_game_id" => niche.gamedb_game_id,
          "vote_count" => 1 }
      ])
      expect(json.fetch("meta")).to eq("cap" => 2)
    end

    it "reports the larger cap for rounds with nine or more nominations" do
      create_list(:gotm_nomination, 9, round_number: round)

      get "/api/v1/gotm_entries/#{round}/votes/tally", headers: auth_headers_for(member)

      expect(json.fetch("meta")).to eq("cap" => 3)
    end

    it "requires authentication" do
      get "/api/v1/gotm_entries/#{round}/votes/tally"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gotm_entries/:round/votes/:user_id" do
    it "shows a voter their own votes while voting is open" do
      schedule_voting!(round)
      vote = create(:gotm_vote, round_number: round, user: member)
      create(:gotm_vote, round_number: round) # someone else's

      during_voting do
        get "/api/v1/gotm_entries/#{round}/votes/#{member.user_id}", headers: auth_headers_for(member)
      end

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |v| v.fetch("vote_id") }).to eq([ vote.vote_id ])
    end

    it "hides another voter's votes from a member while voting is open" do
      schedule_voting!(round)
      vote = create(:gotm_vote, round_number: round)

      during_voting do
        get "/api/v1/gotm_entries/#{round}/votes/#{vote.user_id}", headers: auth_headers_for(member)
      end

      expect(response).to have_http_status(:forbidden)
    end

    it "lets an admin read any voter's votes while voting is open" do
      schedule_voting!(round)
      vote = create(:gotm_vote, round_number: round)

      during_voting do
        get "/api/v1/gotm_entries/#{round}/votes/#{vote.user_id}",
          headers: auth_headers_for(create(:user, :admin))
      end

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").first).to include("vote_id" => vote.vote_id)
    end

    it "opens any voter's votes to members once voting has ended" do
      schedule_voting!(round)
      vote = create(:gotm_vote, round_number: round)

      after_voting do
        get "/api/v1/gotm_entries/#{round}/votes/#{vote.user_id}", headers: auth_headers_for(member)
      end

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
    end

    it "returns an empty array (not 404) when the user has no votes" do
      get "/api/v1/gotm_entries/#{round}/votes/#{member.user_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([])
    end
  end

  describe "DELETE /api/v1/gotm_entries/:round/votes" do
    it "clears the round's votes as an admin, leaving other rounds" do
      round_nomination = create(:gotm_nomination, round_number: round)
      create_list(:gotm_vote, 2, nomination: round_nomination)
      untouched = create(:gotm_vote)

      delete "/api/v1/gotm_entries/#{round}/votes", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(GotmVote.where(round_number: round)).to be_empty
      expect(GotmVote.exists?(untouched.vote_id)).to be(true)
    end

    it "forbids a regular user" do
      create(:gotm_vote, round_number: round)

      delete "/api/v1/gotm_entries/#{round}/votes", headers: auth_headers_for(member)

      expect(response).to have_http_status(:forbidden)
      expect(GotmVote.where(round_number: round)).to exist
    end

    it "requires authentication" do
      delete "/api/v1/gotm_entries/#{round}/votes"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # The NR-GOTM endpoints share the controller/service internals; cover the
  # twin paths and their window gate.
  describe "NR-GOTM twin endpoints" do
    def cast_nr_gotm(round_number, user, nomination, headers)
      post "/api/v1/nr_gotm_entries/#{round_number}/votes",
        params: { data: { user_id: user.user_id, nomination_id: nomination.nomination_id } },
        headers: headers, as: :json
    end

    it "casts and toggles a member's NR vote inside the window" do
      schedule_voting!(round)
      nomination = create(:nr_gotm_nomination, round_number: round)

      during_voting do
        cast_nr_gotm(round, member, nomination, auth_headers_for(member))
        expect(response).to have_http_status(:created)
        expect(json.dig("data", "vote")).to include("nomination_id" => nomination.nomination_id)

        cast_nr_gotm(round, member, nomination, auth_headers_for(member))
        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "action")).to eq("unvoted")
      end

      expect(NrGotmVote.where(round_number: round)).to be_empty
    end

    it "rejects an NR cast outside the voting window" do
      schedule_voting!(round)
      nomination = create(:nr_gotm_nomination, round_number: round)

      before_voting { cast_nr_gotm(round, member, nomination, auth_headers_for(member)) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "voting_closed")
    end

    it "serves the NR tally with the round's cap" do
      nomination = create(:nr_gotm_nomination, round_number: round)
      create(:nr_gotm_vote, nomination: nomination)

      get "/api/v1/nr_gotm_entries/#{round}/votes/tally", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        { "nomination_id" => nomination.nomination_id,
          "gamedb_game_id" => nomination.gamedb_game_id, "vote_count" => 1 }
      ])
      expect(json.fetch("meta")).to eq("cap" => 2)
    end

    it "gates the identified NR list and the reset like the GOTM ones" do
      schedule_voting!(round)
      create(:nr_gotm_vote, round_number: round)

      during_voting { get "/api/v1/nr_gotm_entries/#{round}/votes", headers: auth_headers_for(member) }
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/nr_gotm_entries/#{round}/votes", headers: auth_headers_for(member)
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/nr_gotm_entries/#{round}/votes", headers: service_headers
      expect(json).to eq("deleted" => true, "count" => 1)
      expect(NrGotmVote.where(round_number: round)).to be_empty
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the GOTM / NR-GOTM nomination endpoints (#97): open reads,
# owner-gated writes behind the nomination window (service/admin bypass), and
# the admin round resets. The window rule (BotVotingInfo.nominations_open_for?)
# opens nominations for the round AFTER the current (highest) one and closes
# them when the current round's vote opens.
RSpec.describe "api/v1/nominations behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }

  # Creates the current voting-info round and returns the round number member
  # nominations are open for (current + 1, until vote_opens_at).
  def open_nomination_round!(vote_opens_at = 2.days.from_now)
    create(:voting_info, next_vote_at: vote_opens_at).round_number + 1
  end

  describe "GET /api/v1/gotm_entries/:round/nominations" do
    it "lists the round's nominations oldest first with embedded user and game" do
      round = SecureRandom.random_number(1_000_000_000)
      newer = create(:gotm_nomination, round_number: round, nominated_at: 1.hour.ago)
      older = create(:gotm_nomination, round_number: round, nominated_at: 2.hours.ago)
      create(:gotm_nomination) # another round, filtered out

      get "/api/v1/gotm_entries/#{round}/nominations", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |n| n.fetch("nomination_id") })
        .to eq([ older.nomination_id, newer.nomination_id ])
      expect(json.fetch("data").first).to include(
        "nomination_id" => older.nomination_id,
        "round_number" => round,
        "user_id" => older.user_id,
        "gamedb_game_id" => older.gamedb_game_id,
        "reason" => older.reason
      )
      expect(json.dig("data", 0, "user")).to include("user_id" => older.user_id, "username" => older.user.username)
      expect(json.dig("data", 0, "game")).to include("game_id" => older.gamedb_game_id, "title" => older.game.title)
      expect(json.fetch("meta")).to include("count" => 2)
    end

    it "requires authentication" do
      get "/api/v1/gotm_entries/1/nominations"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gotm_entries/:round/nominations/:user_id" do
    it "returns the user's nomination for the round" do
      nomination = create(:gotm_nomination)

      get "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nomination.user_id}",
        headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "nomination_id" => nomination.nomination_id,
        "user_id" => nomination.user_id
      )
    end

    it "404s when the user has no nomination in the round" do
      nomination = create(:gotm_nomination)

      get "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{member.user_id}",
        headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/gotm_entries/:round/nominations" do
    let(:game) { create(:game) }
    let(:payload) { { data: { user_id: member.user_id, gamedb_game_id: game.game_id, reason: "great pick" } } }

    it "lets a member nominate themselves while the window is open" do
      round = open_nomination_round!

      expect {
        post "/api/v1/gotm_entries/#{round}/nominations",
          params: payload, headers: auth_headers_for(member), as: :json
      }.to change(GotmNomination.where(round_number: round), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "round_number" => round,
        "user_id" => member.user_id,
        "gamedb_game_id" => game.game_id,
        "reason" => "great pick"
      )
    end

    it "replaces the member's existing nomination on re-nominate (upsert, 200)" do
      round = open_nomination_round!
      other_game = create(:game)
      post "/api/v1/gotm_entries/#{round}/nominations",
        params: { data: { user_id: member.user_id, gamedb_game_id: other_game.game_id, reason: "first" } },
        headers: auth_headers_for(member), as: :json

      expect {
        post "/api/v1/gotm_entries/#{round}/nominations",
          params: payload, headers: auth_headers_for(member), as: :json
      }.not_to change(GotmNomination.where(round_number: round), :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("gamedb_game_id" => game.game_id, "reason" => "great pick")
    end

    it "rejects a member nomination once the current round's vote has opened" do
      info = create(:voting_info, next_vote_at: 1.hour.from_now)
      round = info.round_number + 1

      travel_to(2.hours.from_now) do
        post "/api/v1/gotm_entries/#{round}/nominations",
          params: payload, headers: auth_headers_for(member), as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nominations_closed")
      expect(GotmNomination.where(round_number: round)).to be_empty
    end

    it "rejects a member nomination for the current (frozen) round" do
      round = open_nomination_round! - 1 # the current round itself

      post "/api/v1/gotm_entries/#{round}/nominations",
        params: payload, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nominations_closed")
    end

    it "rejects a member nomination when no rounds are scheduled" do
      post "/api/v1/gotm_entries/#{SecureRandom.random_number(1_000_000_000)}/nominations",
        params: payload, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nominations_closed")
    end

    it "lets the service upsert for any user outside any window" do
      post "/api/v1/gotm_entries/#{SecureRandom.random_number(1_000_000_000)}/nominations",
        params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "lets an admin upsert for another user outside any window" do
      post "/api/v1/gotm_entries/#{SecureRandom.random_number(1_000_000_000)}/nominations",
        params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a member nominating on behalf of someone else" do
      round = open_nomination_round!

      post "/api/v1/gotm_entries/#{round}/nominations",
        params: payload, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s when user_id is missing" do
      post "/api/v1/gotm_entries/#{SecureRandom.random_number(1_000_000_000)}/nominations",
        params: { data: { gamedb_game_id: game.game_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/gotm_entries/1/nominations",
        params: { user_id: member.user_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/gotm_entries/1/nominations", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/gotm_entries/:round/nominations/:user_id" do
    it "service-deletes a nomination anytime, clearing only its votes" do
      round = SecureRandom.random_number(1_000_000_000)
      target = create(:gotm_nomination, round_number: round)
      other = create(:gotm_nomination, round_number: round)
      target_vote = create(:gotm_vote, nomination: target)
      other_vote = create(:gotm_vote, nomination: other)

      delete "/api/v1/gotm_entries/#{round}/nominations/#{target.user_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GotmNomination.exists?(target.nomination_id)).to be(false)
      expect(GotmVote.exists?(target_vote.vote_id)).to be(false)
      expect(GotmVote.exists?(other_vote.vote_id)).to be(true)
    end

    it "lets a member withdraw their own nomination while the window is open" do
      round = open_nomination_round!
      create(:gotm_nomination, round_number: round, user: member)

      delete "/api/v1/gotm_entries/#{round}/nominations/#{member.user_id}",
        headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(GotmNomination.where(round_number: round, user_id: member.user_id)).to be_empty
    end

    it "rejects a member withdrawal outside the window" do
      round = SecureRandom.random_number(1_000_000_000) # no rounds scheduled
      create(:gotm_nomination, round_number: round, user: member)

      delete "/api/v1/gotm_entries/#{round}/nominations/#{member.user_id}",
        headers: auth_headers_for(member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nominations_closed")
      expect(GotmNomination.where(round_number: round, user_id: member.user_id)).to exist
    end

    it "forbids a member deleting someone else's nomination" do
      round = open_nomination_round!
      nomination = create(:gotm_nomination, round_number: round)

      delete "/api/v1/gotm_entries/#{round}/nominations/#{nomination.user_id}",
        headers: auth_headers_for(member)

      expect(response).to have_http_status(:forbidden)
      expect(GotmNomination.exists?(nomination.nomination_id)).to be(true)
    end

    it "404s when the user has no nomination in the round" do
      delete "/api/v1/gotm_entries/#{SecureRandom.random_number(1_000_000_000)}/nominations/#{member.user_id}",
        headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/gotm_entries/:round/nominations" do
    it "clears the round's nominations and votes as an admin, leaving other rounds" do
      round = SecureRandom.random_number(1_000_000_000)
      create_list(:gotm_nomination, 2, round_number: round).each do |nomination|
        create(:gotm_vote, nomination: nomination)
      end
      untouched = create(:gotm_nomination)

      delete "/api/v1/gotm_entries/#{round}/nominations", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(GotmNomination.where(round_number: round)).to be_empty
      expect(GotmVote.where(round_number: round)).to be_empty
      expect(GotmNomination.exists?(untouched.nomination_id)).to be(true)
    end

    it "forbids a regular user, even while the window is open" do
      round = open_nomination_round!
      create(:gotm_nomination, round_number: round, user: member)

      delete "/api/v1/gotm_entries/#{round}/nominations", headers: auth_headers_for(member)

      expect(response).to have_http_status(:forbidden)
      expect(GotmNomination.where(round_number: round)).to exist
    end

    it "requires authentication" do
      delete "/api/v1/gotm_entries/1/nominations"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # The NR-GOTM endpoints share the controller helpers; cover the twin paths
  # and the one contract difference (gamedb_game_id is required).
  describe "NR-GOTM twin endpoints" do
    it "lists a round's NR nominations with embedded user and game" do
      nomination = create(:nr_gotm_nomination)

      get "/api/v1/nr_gotm_entries/#{nomination.round_number}/nominations", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").first).to include(
        "nomination_id" => nomination.nomination_id,
        "user_id" => nomination.user_id,
        "gamedb_game_id" => nomination.gamedb_game_id
      )
      expect(json.dig("data", 0, "user")).to include("user_id" => nomination.user_id)
    end

    it "lets a member nominate in-window and rejects them out-of-window" do
      game = create(:game)
      round = open_nomination_round!
      payload = { data: { user_id: member.user_id, gamedb_game_id: game.game_id } }

      post "/api/v1/nr_gotm_entries/#{round}/nominations",
        params: payload, headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:created)

      post "/api/v1/nr_gotm_entries/#{round - 1}/nominations",
        params: payload, headers: auth_headers_for(member), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nominations_closed")
    end

    it "422s when gamedb_game_id is missing (required for NR-GOTM)" do
      post "/api/v1/nr_gotm_entries/#{SecureRandom.random_number(1_000_000_000)}/nominations",
        params: { data: { user_id: member.user_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "deletes one nomination (with its votes) and resets the round as service/admin" do
      round = SecureRandom.random_number(1_000_000_000)
      target = create(:nr_gotm_nomination, round_number: round)
      vote = create(:nr_gotm_vote, nomination: target)
      create(:nr_gotm_nomination, round_number: round)

      delete "/api/v1/nr_gotm_entries/#{round}/nominations/#{target.user_id}", headers: service_headers
      expect(response).to have_http_status(:ok)
      expect(NrGotmNomination.exists?(target.nomination_id)).to be(false)
      expect(NrGotmVote.exists?(vote.vote_id)).to be(false)

      delete "/api/v1/nr_gotm_entries/#{round}/nominations", headers: auth_headers_for(create(:user, :admin))
      expect(json).to eq("deleted" => true, "count" => 1)
      expect(NrGotmNomination.where(round_number: round)).to be_empty
    end

    it "forbids a regular user from the round reset" do
      delete "/api/v1/nr_gotm_entries/1/nominations", headers: auth_headers_for(member)

      expect(response).to have_http_status(:forbidden)
    end
  end
end

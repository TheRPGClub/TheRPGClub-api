# frozen_string_literal: true

require "rails_helper"

# Pool Proposals (spec api#442, ticket api#447; GLOSSARY.md "Pool Proposal"):
# a member who can see a Pool Challenge proposes a game; the Host (staff for
# a club-hosted Challenge) accepts it as Core or Optional, or declines it.
RSpec.describe "api/v1/challenges/:id/pool_proposals", type: :request do
  let(:host) { create(:user, role_member: true) }
  let(:proposer) { create(:user, role_member: true) }
  let(:other) { create(:user, role_member: true) }
  let(:moderator) { create(:user, role_member: true, role_moderator: true) }
  let!(:core_game) { create(:game, title: "Chrono Trigger") }
  let!(:optional_game) { create(:game, title: "Secret of Mana") }
  let!(:excluded_game) { create(:game, title: "Final Fantasy Mystic Quest") }
  let!(:proposed_game) { create(:game, title: "Terranigma") }
  let(:challenge) { pool_challenge(host: host) }

  def pool_challenge(host:)
    challenge = create(:challenge, host: host, pool_optional_target: 0)
    ChallengePoolGame.where(challenge_id: challenge.id).delete_all
    ChallengePoolGame.create!(challenge: challenge, game: core_game, inclusion: "core")
    ChallengePoolGame.create!(challenge: challenge, game: optional_game, inclusion: "optional")
    ChallengePoolGame.create!(challenge: challenge, game: excluded_game, inclusion: "exclude")
    challenge
  end

  def propose(game, on: challenge, as: proposer, note: nil)
    data = { game_id: game.game_id }
    data[:note] = note if note
    post "/api/v1/challenges/#{on.id}/pool_proposals", params: { data: data }, headers: auth_headers_for(as), as: :json
  end

  def proposed(game, on: challenge, as: proposer, note: nil)
    propose(game, on: on, as: as, note: note)
    expect(response).to have_http_status(:created), response.body
    json.dig("data", "id")
  end

  def accept(id, as_kind, on: challenge, as: host)
    post "/api/v1/challenges/#{on.id}/pool_proposals/#{id}/accept", params: { data: { as: as_kind } },
      headers: auth_headers_for(as), as: :json
  end

  def decline(id, on: challenge, as: host)
    post "/api/v1/challenges/#{on.id}/pool_proposals/#{id}/decline", headers: auth_headers_for(as), as: :json
  end

  def pool(on: challenge, as: host)
    get "/api/v1/challenges/#{on.id}", headers: auth_headers_for(as)
    json.dig("data", "pool")
  end

  def ids(games) = games.map { |game| game.fetch("game_id") }

  def dms(event) = BotJob.where(kind: "challenge_dm").where("payload->>'event' = ?", event)

  describe "proposing" do
    it "makes a pending proposal with the proposer's note" do
      propose(proposed_game, note: "A Quintet classic that fits the theme.")

      expect(response).to have_http_status(:created), response.body
      expect(json.fetch("data")).to include("challenge_id" => challenge.id, "status" => "pending",
        "accepted_as" => nil, "note" => "A Quintet classic that fits the theme.", "decided_at" => nil)
      expect(json.dig("data", "game")).to include("game_id" => proposed_game.game_id, "title" => "Terranigma")
      expect(json.dig("data", "proposer", "user_id")).to eq(proposer.user_id)
    end

    it "refuses a game already in the Pool, as Core, Optional or through a source" do
      franchise = create(:franchise)
      sourced = create(:game, title: "Seiken Densetsu 3")
      GamedbGameFranchise.create!(game: sourced, franchise: franchise)
      ChallengePoolFranchise.create!(challenge: challenge, franchise: franchise)

      [ core_game, optional_game, sourced ].each do |game|
        propose(game)
        expect(response).to have_http_status(:conflict)
        expect(json).to include("error" => "already_in_pool")
      end
    end

    it "refuses a game already pending, whoever proposed it, and allows it again once decided" do
      id = proposed(proposed_game)

      propose(proposed_game, as: other)
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "already_proposed", "proposal_id" => id)

      decline(id)
      expect(response).to have_http_status(:ok)
      propose(proposed_game, as: other)
      expect(response).to have_http_status(:created)
    end

    it "allows an excluded game" do
      propose(excluded_game)

      expect(response).to have_http_status(:created)
    end

    it "refuses a note over 280 characters, an unknown game and a Challenge that isn't a Pool" do
      propose(proposed_game, note: "x" * 281)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_proposal")

      post "/api/v1/challenges/#{challenge.id}/pool_proposals", params: { data: { game_id: 0 } },
        headers: auth_headers_for(proposer), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      slots = create(:challenge, challenge_format: "slots", slots_first_year: 1990, slots_last_year: 1999)
      propose(proposed_game, on: slots)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "not_pool")
    end

    it "is only for members who can see the Challenge" do
      challenge.update!(hidden: true)

      propose(proposed_game)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "deciding" do
    it "accepts a proposal as a Core Game" do
      id = proposed(proposed_game)

      accept(id, "core")

      expect(response).to have_http_status(:ok), response.body
      expect(json.fetch("data")).to include("status" => "accepted", "accepted_as" => "core")
      expect(json.dig("data", "decider", "user_id")).to eq(host.user_id)
      expect(json.dig("data", "decided_at")).to be_present
      expect(ids(pool.fetch("core_games"))).to contain_exactly(core_game.game_id, proposed_game.game_id)
    end

    it "accepts a proposal as an Optional Game picked by hand" do
      id = proposed(proposed_game)

      accept(id, "optional")

      expect(response).to have_http_status(:ok)
      optional = pool.fetch("optional_games")
      expect(optional.find { |game| game["game_id"] == proposed_game.game_id }).to include("source" => "hand")
    end

    it "lifts the exclusion of an excluded game it accepts" do
      id = proposed(excluded_game)

      accept(id, "optional")

      current = pool
      expect(ids(current.fetch("excluded_games"))).to be_empty
      expect(ids(current.fetch("optional_games"))).to include(excluded_game.game_id)
    end

    it "declines a proposal, leaving the Pool alone" do
      id = proposed(proposed_game)

      decline(id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("status" => "declined", "accepted_as" => nil)
      expect(ids(pool.fetch("core_games") + pool.fetch("optional_games"))).not_to include(proposed_game.game_id)
    end

    it "refuses to decide twice, and an unknown `as`" do
      id = proposed(proposed_game)

      accept(id, "both")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_proposal")

      decline(id)
      accept(id, "core")
      expect(response).to have_http_status(:conflict)
      expect(json).to include("error" => "already_decided")
    end

    it "is for the Host, not the proposer or other members" do
      id = proposed(proposed_game)

      [ proposer, other ].each do |member|
        accept(id, "core", as: member)
        expect(response).to have_http_status(:forbidden)
        decline(id, as: member)
        expect(response).to have_http_status(:forbidden)
      end
      expect(json.fetch("message")).to eq("Only the Host or a Moderator can accept or decline Pool Proposals.")
    end

    it "is for any Moderator or above on a member's Challenge too" do
      id = proposed(proposed_game)

      accept(id, "core", as: moderator)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "decider", "user_id")).to eq(moderator.user_id)
    end

    it "is for any Moderator or above on a club-hosted Challenge" do
      club = pool_challenge(host: nil)
      id = proposed(proposed_game, on: club)

      accept(id, "core", on: club, as: proposer)
      expect(response).to have_http_status(:forbidden)

      accept(id, "core", on: club, as: moderator)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "reading" do
    let!(:mine) { proposed(proposed_game) }
    let!(:theirs) { proposed(excluded_game, as: other) }

    def index(as:, status: nil)
      get "/api/v1/challenges/#{challenge.id}/pool_proposals", params: { status: status }.compact,
        headers: auth_headers_for(as)
      expect(response).to have_http_status(:ok), response.body
      json.fetch("data").map { |proposal| proposal.fetch("id") }
    end

    it "lists every proposal for the Host and staff, newest first, and only their own for other members" do
      expect(index(as: host)).to eq([ theirs, mine ])
      expect(index(as: moderator)).to eq([ theirs, mine ])
      expect(index(as: proposer)).to eq([ mine ])
    end

    it "filters by status" do
      decline(mine)

      expect(index(as: host, status: "pending")).to eq([ theirs ])
      expect(index(as: host, status: "declined")).to eq([ mine ])
    end

    it "counts the pending proposals on the Challenge for those who decide" do
      decline(mine)

      get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(host)
      expect(json.dig("data", "pending_proposals")).to eq(1)

      get "/api/v1/challenges/#{challenge.id}", headers: auth_headers_for(proposer)
      expect(json.dig("data", "pending_proposals")).to be_nil
    end
  end

  describe "through the bot" do
    it "proposes, reads and decides for the member it names" do
      post "/api/v1/challenges/#{challenge.id}/pool_proposals", headers: service_headers, as: :json,
        params: { data: { acting_user_id: proposer.user_id, game_id: proposed_game.game_id } }
      expect(response).to have_http_status(:created), response.body
      id = json.dig("data", "id")

      get "/api/v1/challenges/#{challenge.id}", params: { acting_user_id: host.user_id }, headers: service_headers
      expect(json.dig("data", "pending_proposals")).to eq(1)

      post "/api/v1/challenges/#{challenge.id}/pool_proposals/#{id}/accept", headers: service_headers, as: :json,
        params: { data: { acting_user_id: proposer.user_id, as: "core" } }
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/challenges/#{challenge.id}/pool_proposals/#{id}/accept", headers: service_headers, as: :json,
        params: { data: { acting_user_id: host.user_id, as: "core" } }
      expect(response).to have_http_status(:ok)
    end

    it "needs a member to act for" do
      post "/api/v1/challenges/#{challenge.id}/pool_proposals", headers: service_headers, as: :json,
        params: { data: { game_id: proposed_game.game_id } }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DMs" do
    let(:club) { pool_challenge(host: nil) }

    it "tells the Host about a new proposal, with the note" do
      expect { proposed(proposed_game, note: "Worth it.") }.to change { dms("pool_proposal").count }.by(1)

      payload = dms("pool_proposal").last.payload
      expect(payload).to include("user_id" => host.user_id, "club_hosted" => false, "feature_key" => "challenges")
      expect(payload.dig("challenge", "id")).to eq(challenge.id)
      expect(payload.fetch("proposal")).to include("note" => "Worth it.", "status" => "pending")
      expect(payload.dig("proposal", "game", "title")).to eq("Terranigma")
      expect(dms("pool_proposal").last.requested_by_user_id).to eq(proposer.user_id)
    end

    it "queues one #dev event without a user for a club-hosted Challenge" do
      expect { proposed(proposed_game, on: club) }.to change { dms("pool_proposal").count }.by(1)

      payload = dms("pool_proposal").last.payload
      expect(payload).to include("club_hosted" => true)
      expect(payload).not_to have_key("user_id")
    end

    it "tells the proposer when it is accepted, and nobody when it is declined" do
      accepted = proposed(proposed_game)
      declined = proposed(excluded_game)

      expect { accept(accepted, "optional") }.to change { dms("pool_proposal_accepted").count }.by(1)
      payload = dms("pool_proposal_accepted").last.payload
      expect(payload).to include("user_id" => proposer.user_id)
      expect(payload.fetch("proposal")).to include("status" => "accepted", "accepted_as" => "optional")
      expect(payload.dig("challenge", "pool", "optional_games").pluck("game_id")).to include(proposed_game.game_id)

      expect { decline(declined) }.not_to(change { BotJob.where(kind: "challenge_dm").count })
    end

    it "sends neither DM to a member who turned Challenge DMs off" do
      host.update!(challenge_dms: false)
      proposer.update!(challenge_dms: false)

      expect { accept(proposed(proposed_game), "core") }.not_to(change { BotJob.where(kind: "challenge_dm").count })
    end

    it "sends no DM to the Host about their own proposal" do
      expect { proposed(proposed_game, as: host) }.not_to(change { dms("pool_proposal").count })
    end

    it "DMs the members in a Run when a Core Game is accepted, as a Pool edit does" do
      create(:challenge_run, challenge: challenge, user: other)

      expect { accept(proposed(proposed_game), "core") }.to change { dms("pool_goal_changed").count }.by(1)
      expect(dms("pool_goal_changed").last.payload.fetch("added_core_games").pluck("game_id"))
        .to eq([ proposed_game.game_id ])
    end
  end
end

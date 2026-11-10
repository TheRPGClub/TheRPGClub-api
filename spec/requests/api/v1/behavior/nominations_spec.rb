# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the GOTM / NR-GOTM nomination endpoints (#97): open reads,
# owner-gated writes behind the nomination window (service/admin bypass), and
# the admin round resets. The window rule (VotingRound.nominations_open_for?)
# opens nominations for the current round only, until its vote opens.
RSpec.describe "api/v1/nominations behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }

  # Creates the current voting round and returns its number: member
  # nominations are open for it until vote_opens_at.
  def open_nomination_round!(vote_opens_at = 2.days.from_now)
    create(:voting_round, voting_opens_at: vote_opens_at).round_number
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

    # The board renders a pill per platform, so the embedded game carries them
    # (GameWithPlatformsResource) rather than the platform-free GameSummary.
    it "embeds each game's platforms, ordered by name" do
      round = SecureRandom.random_number(1_000_000_000)
      game = create(:game)
      zulu = create(:platform, platform_name: "Zulu Station")
      alpha = create(:platform, platform_name: "Alpha Deck")
      create(:game_platform, game: game, platform: zulu)
      create(:game_platform, game: game, platform: alpha)
      create(:gotm_nomination, round_number: round, game: game)

      get "/api/v1/gotm_entries/#{round}/nominations", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      platforms = json.dig("data", 0, "game", "platforms")
      expect(platforms.map { |p| p.fetch("platform_name") }).to eq([ "Alpha Deck", "Zulu Station" ])
      expect(platforms.first).to include(
        "platform_id" => alpha.platform_id,
        "platform_code" => alpha.platform_code,
        "platform_abbreviation" => alpha.platform_abbreviation
      )
    end

    # The point of the embed: a board of 10-20 nominations must not turn into
    # one platforms query per row. Bullet (raise: true in test) already fails
    # the request on an N+1; this pins the count so a later refactor that drops
    # the preload fails here with the reason spelled out.
    it "loads platforms for the whole board in one query" do
      round = SecureRandom.random_number(1_000_000_000)
      3.times do
        game = create(:game)
        create(:game_platform, game: game, platform: create(:platform))
        create(:gotm_nomination, round_number: round, game: game)
      end

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql]
      end
      begin
        get "/api/v1/gotm_entries/#{round}/nominations", headers: auth_headers_for(member)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").size).to eq(3)
      expect(json.fetch("data").map { |n| n.dig("game", "platforms").size }).to all(eq(1))
      expect(queries.count { |sql| sql.include?("gamedb_platforms") }).to eq(1)
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
      round = open_nomination_round!(1.hour.from_now)

      travel_to(2.hours.from_now) do
        post "/api/v1/gotm_entries/#{round}/nominations",
          params: payload, headers: auth_headers_for(member), as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "nominations_closed")
      expect(GotmNomination.where(round_number: round)).to be_empty
    end

    it "rejects a member nomination for any round but the current one" do
      round = open_nomination_round! + 1

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
      expect(json).to eq("deleted" => true, "meta" => { "announce_job_id" => nil })
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

  # An Admin removing someone else's nomination (#332): a reason is required,
  # and a nomination_deleted job tells the nomination channel. Owners and the
  # service keep the plain delete with no job.
  describe "DELETE /api/v1/gotm_entries/:round/nominations/:user_id with a reason" do
    let(:nominator) { create(:user, username: "chrono_fan") }
    let(:game) { create(:game, title: "Chrono Trigger") }

    def nomination_in_open_round!
      create(:gotm_nomination, round_number: open_nomination_round!, user: nominator, game: game)
    end

    callers = {
      "anonymous" => [ nil, :unauthorized, false ],
      "a plain member" => [ -> { auth_headers_for(create(:user)) }, :forbidden, false ],
      "a Members role holder" => [ -> { auth_headers_for(create(:user, role_member: true)) }, :forbidden, false ],
      "a Regulars role holder" => [ -> { auth_headers_for(create(:user, role_regular: true)) }, :forbidden, false ],
      "a Moderator" => [ -> { auth_headers_for(create(:user, role_moderator: true)) }, :forbidden, false ],
      "an Admin" => [ -> { auth_headers_for(create(:user, :admin)) }, :ok, true ],
      "a Superadmin" => [ -> { auth_headers_for(create(:user), is_dev: true) }, :ok, true ],
      "the service" => [ -> { service_headers }, :ok, false ]
    }

    callers.each do |label, (headers_for, status, queues_job)|
      it "answers #{status} to #{label}#{queues_job ? ' and queues the announcement' : ''}" do
        nomination = nomination_in_open_round!
        headers = headers_for ? instance_exec(&headers_for) : {}

        expect {
          delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
            params: { reason: "Not an RPG" }, headers: headers
        }.to change(BotJob.where(kind: "nomination_deleted"), :count).by(queues_job ? 1 : 0)

        expect(response).to have_http_status(status)
        expect(GotmNomination.exists?(nomination.nomination_id)).to be(status != :ok)
      end
    end

    it "queues nomination_deleted with the details captured before the delete" do
      nomination = nomination_in_open_round!
      admin = create(:user, :admin)

      delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
        params: { reason: "  Not an RPG  " }, headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      job = BotJob.last
      expect(json).to eq("deleted" => true, "meta" => { "announce_job_id" => job.id })
      expect(job.kind).to eq("nomination_deleted")
      expect(job.payload).to eq(
        "category" => "gotm",
        "round_number" => nomination.round_number,
        "user_id" => nominator.user_id,
        "game_title" => "Chrono Trigger",
        "deleted_by_user_id" => admin.user_id,
        "reason" => "Not an RPG",
        "feature_key" => "voting_gotm"
      )
      expect(job.summary).to eq(
        %(Announce that chrono_fan's GOTM round #{nomination.round_number} nomination "Chrono Trigger" was removed)
      )
      expect(job.requested_by_user_id).to eq(admin.user_id)
    end

    it "lets an Admin remove a nomination outside the window" do
      nomination = create(:gotm_nomination, round_number: SecureRandom.random_number(1_000_000_000),
        user: nominator, game: game)

      delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
        params: { reason: "Late fix" }, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(BotJob.last.payload).to include("reason" => "Late fix")
    end

    it "requires a reason when an Admin removes someone else's nomination" do
      nomination = nomination_in_open_round!

      [ {}, { reason: "   " } ].each do |params|
        expect {
          delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
            params: params, headers: auth_headers_for(create(:user, :admin))
        }.not_to change(BotJob, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("error" => "reason_required")
      end
      expect(GotmNomination.exists?(nomination.nomination_id)).to be(true)
    end

    it "refuses a reason over 250 characters" do
      nomination = nomination_in_open_round!

      delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
        params: { reason: "x" * 251 }, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "reason_too_long")
      expect(GotmNomination.exists?(nomination.nomination_id)).to be(true)
    end

    it "keeps the plain delete for an owner withdrawing in the window, with or without a reason" do
      nomination = nomination_in_open_round!

      expect {
        delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
          params: { reason: "changed my mind" }, headers: auth_headers_for(nominator)
      }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "meta" => { "announce_job_id" => nil })
      expect(GotmNomination.exists?(nomination.nomination_id)).to be(false)
    end

    it "keeps the plain delete for an Admin withdrawing their own nomination" do
      admin = create(:user, :admin)
      nomination = create(:gotm_nomination, round_number: open_nomination_round!, user: admin)

      expect {
        delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{admin.user_id}",
          headers: auth_headers_for(admin)
      }.not_to change(BotJob, :count)

      expect(response).to have_http_status(:ok)
    end

    it "sends a null game title when the GOTM nomination has no game" do
      nomination = create(:gotm_nomination, round_number: open_nomination_round!, user: nominator, game: nil)

      delete "/api/v1/gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
        params: { reason: "Empty pick" }, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(BotJob.last.payload).to include("game_title" => nil)
      expect(BotJob.last.summary).to eq(
        "Announce that chrono_fan's GOTM round #{nomination.round_number} nomination was removed"
      )
    end

    it "queues the NR-GOTM category from the NR-GOTM path" do
      nomination = create(:nr_gotm_nomination, round_number: open_nomination_round!, user: nominator, game: game)

      delete "/api/v1/nr_gotm_entries/#{nomination.round_number}/nominations/#{nominator.user_id}",
        params: { reason: "Not a non-RPG" }, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(NrGotmNomination.exists?(nomination.nomination_id)).to be(false)
      expect(BotJob.last.payload).to include("category" => "nr_gotm", "game_title" => "Chrono Trigger")
      expect(BotJob.last.summary).to eq(
        %(Announce that chrono_fan's NR-GOTM round #{nomination.round_number} nomination "Chrono Trigger" was removed)
      )
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

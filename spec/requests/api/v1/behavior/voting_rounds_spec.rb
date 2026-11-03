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

    it "wakes the bot's voting poller for the admin's change" do
      patch "/api/v1/voting_rounds/#{base}", params: { data: { voting_opens_at: (opens_at + 7.days).iso8601 } },
        headers: auth_headers_for(admin), as: :json

      job = BotJob.sole
      expect(job).to have_attributes(kind: "voting_poll_wakeup", payload: {},
        summary: "Wake the voting poller: round #{base} was rescheduled", requested_by_user_id: admin.user_id)
    end

    it "queues nothing when the change is refused" do
      round.update!(decided_at: opens_at + 3.days)

      patch "/api/v1/voting_rounds/#{base}", params: { data: { month_year: "Whenever" } },
        headers: auth_headers_for(admin), as: :json

      expect(BotJob.count).to eq(0)
    end

    it "refuses to move the close to now when voting is not open" do
      travel_to(round.voting_closes_at + 1.hour) do
        patch "/api/v1/voting_rounds/#{base}", params: { data: { voting_closes_at: Time.current.iso8601 } },
          headers: auth_headers_for(admin), as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "voting_not_open")
      expect(BotJob.count).to eq(0)
    end

    it "closes voting early when the close is moved to now" do
      travel_to(opens_at + 1.hour) do
        patch "/api/v1/voting_rounds/#{base}", params: { data: { voting_closes_at: Time.current.iso8601 } },
          headers: auth_headers_for(admin), as: :json
      end

      expect(json.dig("data", "phase")).to eq("closed")
      expect(BotJob.sole).to have_attributes(kind: "voting_poll_wakeup", requested_by_user_id: admin.user_id,
        summary: "Wake the voting poller: voting on round #{base} was closed")
    end

    it "queues nothing for the bot's own change through the service" do
      travel_to(opens_at + 1.hour) do
        patch "/api/v1/voting_rounds/#{base}", params: { data: { voting_closes_at: Time.current.iso8601 } },
          headers: service_headers, as: :json
      end

      expect(json.dig("data", "phase")).to eq("closed")
      expect(BotJob.count).to eq(0)
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

    it "queues the tie-break announcement and wakes the voting poller" do
      winner = games.first
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "gotm", gamedb_game_ids: [ winner.game_id ] } },
        headers: auth_headers_for(admin), as: :json

      announce, wakeup = BotJob.order(:id).to_a
      expect(announce).to have_attributes(kind: "voting_tie_broken", requested_by_user_id: admin.user_id,
        summary: "Announce the GOTM tie break for round #{base}: #{winner.title}",
        payload: { "round_number" => base, "category" => "gotm",
                   "games" => [ { "game_id" => winner.game_id, "title" => winner.title } ] })
      expect(wakeup).to have_attributes(kind: "voting_poll_wakeup",
        summary: "Wake the voting poller: the GOTM tie for round #{base} was broken")
    end

    it "queues nothing for the bot's own tie break through the service, which it announced itself" do
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "gotm", gamedb_game_ids: [ games.first.game_id ] } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(BotJob.count).to eq(0)
    end

    it "queues nothing for a refused pick" do
      post "/api/v1/voting_rounds/#{base}/resolve_tie",
        params: { data: { category: "gotm", gamedb_game_ids: [ create(:game).game_id ] } },
        headers: auth_headers_for(admin), as: :json

      expect(BotJob.count).to eq(0)
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

  # Every caller the staff tools answer, and the status each gets from an
  # Admin-gated action that would otherwise succeed.
  admin_gate = {
    "anonymous" => [ nil, :unauthorized ],
    "a plain member" => [ -> { auth_headers_for(create(:user)) }, :forbidden ],
    "a Members role holder" => [ -> { auth_headers_for(create(:user, role_member: true)) }, :forbidden ],
    "a Regulars role holder" => [ -> { auth_headers_for(create(:user, role_regular: true)) }, :forbidden ],
    "a Moderator" => [ -> { auth_headers_for(create(:user, role_moderator: true)) }, :forbidden ],
    "an Admin" => [ -> { auth_headers_for(create(:user, :admin)) }, :accepted ],
    "a Superadmin" => [ -> { auth_headers_for(create(:user), is_dev: true) }, :accepted ],
    "the service" => [ -> { service_headers }, :accepted ]
  }

  describe "POST /api/v1/voting_rounds/:id/publish_results" do
    let!(:round) { create(:voting_round, round_number: base, voting_opens_at: opens_at, month_year: "November 2026") }
    let(:ended_at) { round.voting_closes_at + 1.hour }

    def publish(headers, round_number = base)
      post "/api/v1/voting_rounds/#{round_number}/publish_results", headers: headers, as: :json
    end

    admin_gate.each do |label, (headers_for, status)|
      it "answers #{status} to #{label}" do
        headers = headers_for ? instance_exec(&headers_for) : {}
        travel_to(ended_at) { publish(headers) }

        expect(response).to have_http_status(status)
        expect(BotJob.count).to eq(status == :accepted ? 1 : 0)
      end
    end

    it "queues the results post with the round number and month label" do
      travel_to(ended_at) { publish(auth_headers_for(admin)) }

      job = BotJob.sole
      expect(job).to have_attributes(kind: "voting_results_publish", requested_by_user_id: admin.user_id,
        summary: "Publish the results of round #{base} (November 2026)",
        payload: { "round_number" => base, "month_label" => "November 2026" })
      expect(json.fetch("data")).to include("id" => job.id, "kind" => "voting_results_publish", "status" => "queued")
      expect(json.fetch("data")).not_to have_key("payload")
    end

    it "may be repeated, queueing a job each time" do
      travel_to(ended_at) { 2.times { publish(auth_headers_for(admin)) } }

      expect(BotJob.where(kind: "voting_results_publish").count).to eq(2)
    end

    it "refuses before voting ends" do
      travel_to(opens_at + 1.hour) { publish(auth_headers_for(admin)) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "voting_not_ended")
      expect(BotJob.count).to eq(0)
    end

    it "refuses while nominations are still open" do
      travel_to(opens_at - 1.day) { publish(auth_headers_for(admin)) }

      expect(json).to include("error" => "voting_not_ended")
    end

    # As the bot's /admin voting-results publish: the main vote's results are
    # final once it closes. A tie in them is announced as going to the runoff
    # (or to the admins), and the runoff's own results post separately.
    it "publishes the main vote's results while a runoff is open" do
      ties = { "gotm" => create_list(:game, 2).map(&:game_id).sort }
      closed_at = round.voting_closes_at
      round.update!(closed_at: closed_at, pending_ties: ties, runoff_ties: ties, runoff_opens_at: closed_at,
        runoff_closes_at: closed_at + 1.day)

      travel_to(ended_at) do
        expect(round.phase).to eq("runoff")
        publish(auth_headers_for(admin))
      end

      expect(response).to have_http_status(:accepted)
    end

    it "publishes the main vote's results while a tie waits for the admins" do
      round.update!(closed_at: round.voting_closes_at, pending_ties: { "gotm" => create_list(:game, 2).map(&:game_id) })

      travel_to(ended_at) do
        expect(round.phase).to eq("tie")
        publish(auth_headers_for(admin))
      end

      expect(response).to have_http_status(:accepted)
    end

    it "publishes a decided round" do
      round.update!(decided_at: ended_at)

      travel_to(ended_at + 1.day) { publish(auth_headers_for(admin)) }

      expect(response).to have_http_status(:accepted)
    end

    [ true, false ].each do |flag|
      it "works with voting automation #{flag ? 'on' : 'off'}" do
        allow(Voting).to receive(:automation_enabled?).and_return(flag)

        travel_to(ended_at) { publish(auth_headers_for(admin)) }

        expect(response).to have_http_status(:accepted)
      end
    end

    it "takes the month from the GOTM entries for a round from before voting rounds" do
      old = base - 5
      create(:gotm_entry, round_number: old, month_year: "March 2019")

      travel_to(ended_at) { publish(auth_headers_for(admin), old) }

      expect(response).to have_http_status(:accepted)
      expect(BotJob.sole.payload).to eq("round_number" => old, "month_label" => "March 2019")
    end

    it "404s for a round that never existed" do
      publish(auth_headers_for(admin), base - 5)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/voting_rounds/current/repost_panels" do
    let!(:round) { create(:voting_round, round_number: base, voting_opens_at: opens_at) }

    def repost(headers)
      post "/api/v1/voting_rounds/current/repost_panels", headers: headers, as: :json
    end

    admin_gate.each do |label, (headers_for, status)|
      it "answers #{status} to #{label}" do
        headers = headers_for ? instance_exec(&headers_for) : {}
        travel_to(opens_at + 1.hour) { repost(headers) }

        expect(response).to have_http_status(status)
        expect(BotJob.count).to eq(status == :accepted ? 1 : 0)
      end
    end

    it "queues the panel repost for the round being voted on" do
      travel_to(opens_at + 1.hour) { repost(auth_headers_for(admin)) }

      job = BotJob.sole
      expect(job).to have_attributes(kind: "voting_panels_repost", requested_by_user_id: admin.user_id,
        summary: "Repost the voting panels for round #{base}", payload: { "round_number" => base })
      expect(json.fetch("data")).to include("id" => job.id, "kind" => "voting_panels_repost")
    end

    {
      "nominations are still open" => -> { opens_at - 1.day },
      "voting has closed" => -> { round.voting_closes_at + 1.hour }
    }.each do |label, at|
      it "refuses when #{label}" do
        travel_to(instance_exec(&at)) { repost(auth_headers_for(admin)) }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("error" => "voting_not_open")
        expect(BotJob.count).to eq(0)
      end
    end

    [ true, false ].each do |flag|
      it "works with voting automation #{flag ? 'on' : 'off'}" do
        allow(Voting).to receive(:automation_enabled?).and_return(flag)

        travel_to(opens_at + 1.hour) { repost(auth_headers_for(admin)) }

        expect(response).to have_http_status(:accepted)
      end
    end

    it "404s when no round is scheduled" do
      round.destroy!

      repost(auth_headers_for(admin))

      expect(response).to have_http_status(:not_found)
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

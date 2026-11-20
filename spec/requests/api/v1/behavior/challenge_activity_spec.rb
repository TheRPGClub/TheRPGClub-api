# frozen_string_literal: true

require "rails_helper"

# Challenge Activity (spec api#421, ticket api#424): the club-wide feed of
# recent Challenge happenings for the dashboard's Challenge Activity panel,
# derived from what Runs, their entries and Editions already store.
RSpec.describe "api/v1/challenge activity behavior", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:player) { create(:user, role_member: true, global_name: "Rinoa") }
  let(:challenge) { create(:challenge, name: "Fall of Final Fantasy") }

  def club_time(text) = ActiveSupport::TimeZone[Challenges::TIME_ZONE].parse(text)

  def activity(as: member, **params)
    get "/api/v1/challenge_activity", params: params, headers: auth_headers_for(as)
  end

  def kinds = json.fetch("data").map { |event| event.fetch("kind") }

  it "lists a Run started with its member and Challenge" do
    run = create(:challenge_run, challenge: challenge, user: player, started_at: club_time("2026-11-10 09:00"))

    activity

    expect(response).to have_http_status(:ok)
    event = json.fetch("data").sole
    expect(event).to include("kind" => "run_started", "occurred_on" => "2026-11-10", "run_id" => run.id,
      "game" => nil, "edition" => nil)
    expect(Time.zone.parse(event.fetch("occurred_at"))).to eq(club_time("2026-11-10 09:00"))
    expect(event.fetch("challenge")).to include("id" => challenge.id, "name" => "Fall of Final Fantasy",
      "tint" => { "fill" => challenge.tint_fill, "hi" => challenge.tint_hi })
    expect(event.dig("user", "user_id")).to eq(player.user_id)
  end

  it "lists a game Cleared on a Run with its game, and a Run Finished" do
    game = create(:game, title: "Final Fantasy VIII")
    run = create(:challenge_run, challenge: challenge, user: player, started_at: club_time("2026-11-01 09:00"),
      status: "finished", ended_at: club_time("2026-11-12 20:30"))
    ChallengeRunEntry.create!(run: run, game: game, state: "cleared", cleared_on: Date.new(2026, 11, 12))
    ChallengeRunEntry.create!(run: run, game: create(:game), state: "in_progress")

    activity

    expect(kinds).to eq(%w[run_finished game_cleared run_started])
    finished, cleared = json.fetch("data")
    expect(finished).to include("occurred_on" => "2026-11-12", "run_id" => run.id, "game" => nil)
    expect(cleared).to include("occurred_on" => "2026-11-12", "occurred_at" => nil, "run_id" => run.id)
    expect(cleared.dig("game", "title")).to eq("Final Fantasy VIII")
    expect(cleared.dig("user", "user_id")).to eq(player.user_id)
  end

  it "leaves out Runs that ended without Finishing" do
    %w[expired abandoned].each do |status|
      create(:challenge_run, challenge: challenge, user: create(:user), status: status,
        started_at: club_time("2026-11-01 09:00"), ended_at: club_time("2026-11-12 20:30"))
    end

    activity

    expect(kinds).to eq(%w[run_started run_started])
  end

  it "leaves out hidden and removed Challenges, for staff too" do
    hidden = create(:challenge, hidden: true)
    create(:challenge_run, challenge: hidden, user: player)
    removed = create(:challenge)
    create(:challenge_run, challenge: removed, user: player)
    removed.destroy!
    create(:challenge_run, challenge: challenge, user: player)

    activity(as: create(:user, role_member: true, role_moderator: true))

    expect(json.fetch("data").map { |event| event.dig("challenge", "id") }).to eq([ challenge.id ])
  end

  it "lists the newest `per` events of every kind together, newest first" do
    run = create(:challenge_run, challenge: challenge, user: player, started_at: club_time("2026-11-01 09:00"),
      status: "finished", ended_at: club_time("2026-11-14 10:00"))
    ChallengeRunEntry.create!(run: run, game: create(:game), state: "cleared", cleared_on: Date.new(2026, 11, 14))
    ChallengeRunEntry.create!(run: run, game: create(:game), state: "cleared", cleared_on: Date.new(2026, 11, 5))
    create(:challenge_run, challenge: create(:challenge), user: member, started_at: club_time("2026-11-08 18:00"))

    activity(per: 3)

    expect(kinds).to eq(%w[run_finished game_cleared run_started])
    expect(json.fetch("data").map { |event| event.fetch("occurred_on") }).to eq(%w[2026-11-14 2026-11-14 2026-11-08])
    expect(json.fetch("meta")).to eq("per" => 3)

    activity
    expect(kinds).to eq(%w[run_finished game_cleared run_started game_cleared run_started])
  end

  it "is not found for a member while Challenges is in Preview, and answers staff" do
    set_feature_flag("challenges", "preview")

    activity
    expect(response).to have_http_status(:not_found)

    activity(as: create(:user, role_member: true, role_admin: true))
    expect(response).to have_http_status(:ok)
  end

  describe "Secret Santa" do
    let(:santa) { create(:challenge, :club_hosted, name: "Secret Santa", challenge_format: "assignment") }

    def edition(year, phase)
      ChallengeEdition.create!(challenge: santa, year: year, phase: phase,
        signup_opens_on: Date.new(year - 1, 12, 26), signup_cutoff_on: Date.new(year, 12, 1),
        pick_deadline_on: Date.new(year, 12, 15), reveal_on: Date.new(year, 12, 25),
        ends_on: Date.new(year + 1, 12, 25))
    end

    it "lists sign-ups opening, and the reveal once it has happened" do
      revealed = edition(2025, "revealed")
      picking = edition(2026, "picking")

      activity

      expect(kinds).to eq(%w[signups_opened edition_revealed signups_opened])
      opened, reveal, earlier = json.fetch("data")
      expect(opened).to include("occurred_on" => "2025-12-26", "occurred_at" => nil, "user" => nil, "game" => nil,
        "run_id" => nil, "edition" => { "id" => picking.id, "year" => 2026 })
      expect(opened.dig("challenge", "name")).to eq("Secret Santa")
      expect(reveal).to include("occurred_on" => "2025-12-25", "edition" => { "id" => revealed.id, "year" => 2025 })
      expect(earlier).to include("occurred_on" => "2024-12-26")
    end

    it "lists the reveal of an Edition that has ended, but nothing of a cancelled one's reveal" do
      edition(2024, "ended")
      edition(2025, "cancelled")

      activity

      expect(kinds).to eq(%w[signups_opened edition_revealed signups_opened])
    end
  end
end

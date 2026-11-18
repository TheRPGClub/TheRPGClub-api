# frozen_string_literal: true

require "rails_helper"

# A Pool Challenge's progress by game (spec #376, the clients' Pool view):
# each Pool game with the members who Cleared it and those who have it In
# Progress, over the Season running now (or the last one) or, for an Always
# Open Challenge, every Run.
RSpec.describe "api/v1/challenges pool progress behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:alice) { create(:user, role_member: true, discord_avatar: "abc") }
  let(:bob) { create(:user, role_member: true) }

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  def game(title, year)
    create(:game, title: title, initial_release_date: Time.utc(year, 1, 1))
  end

  def pool_of(challenge, *games)
    ChallengePoolGame.where(challenge_id: challenge.id).delete_all
    games.each { |pool_game| ChallengePoolGame.create!(challenge: challenge, game: pool_game, inclusion: "include") }
    challenge.reload
  end

  def run_with(challenge, user, status: "active", cleared: {}, playing: [], **attrs)
    create(:challenge_run, challenge: challenge, user: user, status: status, **attrs).tap do |run|
      cleared.each { |cleared_game, on| ChallengeRunEntry.create!(run: run, game: cleared_game, state: "cleared", cleared_on: on) }
      playing.each { |played| ChallengeRunEntry.create!(run: run, game: played, state: "in_progress") }
    end
  end

  def pool_progress(challenge, as: member, **params)
    get "/api/v1/challenges/#{challenge.id}/pool_progress", params: params, headers: auth_headers_for(as)
  end

  def by_title = json.fetch("data").to_h do |row|
    [ row["title"], [ row["cleared_by"].map { |m| m["user_id"] }, row["in_progress"].map { |m| m["user_id"] } ] ]
  end

  it "lists each Pool game, oldest release first, with who Cleared it and who has it In Progress" do
    chrono, ff6, okami = game("Chrono Trigger", 1995), game("Final Fantasy VI", 1994), game("Okami", 2006)
    challenge = pool_of(create(:challenge), chrono, ff6, okami)
    alice_run = run_with(challenge, alice, cleared: { chrono => Date.new(2026, 10, 1) }, playing: [ okami ])
    run_with(challenge, bob, status: "abandoned", cleared: { chrono => Date.new(2026, 9, 1) }, playing: [ ff6 ])

    pool_progress(challenge)

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data").map { |row| row["title"] }).to eq([ "Final Fantasy VI", "Chrono Trigger", "Okami" ])
    expect(by_title).to eq(
      "Final Fantasy VI" => [ [], [] ],
      "Chrono Trigger" => [ [ bob.user_id, alice.user_id ], [] ],
      "Okami" => [ [], [ alice.user_id ] ]
    )
    chrono_row = json.fetch("data").find { |row| row["title"] == "Chrono Trigger" }
    expect(chrono_row).to include("game_id" => chrono.game_id, "cover_url" => nil)
    expect(chrono_row.fetch("cleared_by").last).to include("user_id" => alice.user_id, "discord_avatar" => "abc",
      "run_id" => alice_run.id, "cleared_on" => "2026-10-01")
    expect(json.fetch("meta")).to include("window" => nil, "count" => 3)
  end

  it "reads the Season running now, or the last one while Closed" do
    chrono = game("Chrono Trigger", 1995)
    autumn = pool_of(create(:challenge, :seasonal, season: "09-01..11-30"), chrono)
    this_season = { season_starts_on: Date.new(2026, 9, 1), season_ends_on: Date.new(2026, 11, 30) }
    last_season = { season_starts_on: Date.new(2025, 9, 1), season_ends_on: Date.new(2025, 11, 30) }
    run_with(autumn, alice, cleared: { chrono => Date.new(2026, 10, 1) }, **this_season)
    run_with(autumn, bob, status: "finished", cleared: { chrono => Date.new(2025, 10, 1) }, **last_season)

    pool_progress(autumn)

    expect(by_title).to eq("Chrono Trigger" => [ [ alice.user_id ], [] ])
    expect(json.dig("meta", "window")).to eq("starts_on" => "2026-09-01", "ends_on" => "2026-11-30")

    summer = pool_of(create(:challenge, :seasonal, season: "06-21..09-22"), chrono)
    run_with(summer, bob, status: "expired", cleared: { chrono => Date.new(2026, 7, 1) },
      season_starts_on: Date.new(2026, 6, 21), season_ends_on: Date.new(2026, 9, 22))

    pool_progress(summer)

    expect(by_title).to eq("Chrono Trigger" => [ [ bob.user_id ], [] ])
    expect(json.dig("meta", "window")).to eq("starts_on" => "2026-06-21", "ends_on" => "2026-09-22")
  end

  it "names a member once per game, and pages the Pool" do
    games = (1..3).map { |n| game("Game #{n}", 1990 + n) }
    challenge = pool_of(create(:challenge), *games)
    run_with(challenge, alice, status: "abandoned", cleared: { games[0] => Date.new(2026, 1, 5) })
    run_with(challenge, alice, cleared: { games[0] => Date.new(2026, 9, 5) })

    pool_progress(challenge, per: 2)

    expect(json.fetch("data").size).to eq(2)
    expect(json.dig("data", 0, "cleared_by").sole).to include("user_id" => alice.user_id, "cleared_on" => "2026-01-05")
    expect(json.dig("meta", "next")).to eq(2)
  end

  it "refuses a Challenge without a Pool, and hides a hidden one" do
    slots = create(:challenge, challenge_format: "slots", slots_first_year: 1990, slots_last_year: 1999)

    pool_progress(slots)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.fetch("error")).to eq("not_pool")

    pool_progress(create(:challenge, hidden: true))
    expect(response).to have_http_status(:not_found)
  end
end

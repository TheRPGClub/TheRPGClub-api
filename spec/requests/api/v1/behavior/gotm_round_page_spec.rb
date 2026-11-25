# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Round Page (GET /api/v1/gotm_rounds/:round): one
# closed round in full, per Category its winners, its Nominations and, when
# the round had a vote, the anonymous vote counts and any runoff.
RSpec.describe "api/v1/gotm_rounds/:round behavior", type: :request do
  let(:headers) { auth_headers_for(create(:user)) }

  def decided_round(number, **attrs)
    create(:voting_round, round_number: number, voting_opens_at: 10.days.ago, voting_closes_at: 8.days.ago,
      closed_at: 8.days.ago, decided_at: 8.days.ago, **attrs)
  end

  def show(number)
    get "/api/v1/gotm_rounds/#{number}", headers: headers
  end

  def category(kind = "gotm")
    json.dig("data", kind)
  end

  def nomination_ids(kind = "gotm")
    category(kind).fetch("nominations").map { |nomination| nomination.fetch("nomination_id") }
  end

  it "returns a pre-nomination round with its winners only" do
    entry = create(:gotm_entry, round_number: 120, month_year: "March 2024", reddit_url: "https://reddit.example/120")
    nr = create(:nr_gotm_entry, round_number: 120, month_year: "March 2024")

    show(120)

    expect(response).to have_http_status(:ok)
    data = json.fetch("data")
    expect(data).to include("round_number" => 120, "month_year" => "March 2024")
    expect(category).to include("voted" => false, "runoff" => false, "nominations" => [])
    expect(category.fetch("winners").length).to eq(1)
    expect(category.dig("winners", 0)).to include(
      "game_index" => 0, "gamedb_game_id" => entry.gamedb_game_id,
      "reddit_url" => "https://reddit.example/120", "nomination" => nil
    )
    expect(category.dig("winners", 0, "game")).to include("game_id" => entry.gamedb_game_id, "title" => entry.game.title)
    expect(category("nr_gotm").dig("winners", 0, "gamedb_game_id")).to eq(nr.gamedb_game_id)
  end

  it "lists a nominated round without votes by when each game was nominated, with no counts" do
    decided_round(133)
    create(:gotm_entry, round_number: 133)
    late = create(:gotm_nomination, round_number: 133, nominated_at: 2.days.ago)
    early = create(:gotm_nomination, round_number: 133, nominated_at: 5.days.ago, reason: "Peak JRPG")

    show(133)

    expect(category).to include("voted" => false, "runoff" => false)
    expect(nomination_ids).to eq([ early.nomination_id, late.nomination_id ])
    expect(category.dig("nominations", 0)).to include(
      "user_id" => early.user_id, "gamedb_game_id" => early.gamedb_game_id, "reason" => "Peak JRPG",
      "votes" => nil, "runoff_votes" => nil
    )
    expect(category.dig("nominations", 0, "user")).to include("user_id" => early.user_id)
    expect(category.dig("nominations", 0, "game")).to include("game_id" => early.gamedb_game_id)
    expect(category.dig("nominations", 0, "nominated_at")).to be_present
  end

  it "counts a voted round's votes per Nomination, most votes first, without voter identities" do
    decided_round(144)
    winner_game = create(:game)
    create(:gotm_entry, round_number: 144, game: winner_game)
    winning = create(:gotm_nomination, round_number: 144, game: winner_game, nominated_at: 6.days.ago)
    second = create(:gotm_nomination, round_number: 144, nominated_at: 5.days.ago)
    unvoted = create(:gotm_nomination, round_number: 144, nominated_at: 7.days.ago)
    voters = create_list(:user, 3)
    voters.each { |voter| create(:gotm_vote, nomination: winning, user: voter) }
    create(:gotm_vote, nomination: second, user: voters.first)

    show(144)

    expect(category).to include("voted" => true, "runoff" => false)
    expect(category.dig("winners", 0, "nomination")).to include("nomination_id" => winning.nomination_id, "votes" => 3)
    expect(nomination_ids).to eq([ second.nomination_id, unvoted.nomination_id ])
    expect(category.fetch("nominations").map { |n| n.fetch("votes") }).to eq([ 1, 0 ])
    expect(category.fetch("nominations").map { |n| n.fetch("runoff_votes") }).to eq([ nil, nil ])
    expect(response.body).not_to include(*voters.map(&:user_id))
  end

  it "adds runoff counts for the tied games when the round had a runoff" do
    tied_a = create(:game)
    tied_b = create(:game)
    decided_round(150, runoff_ties: { "gotm" => [ tied_a.game_id, tied_b.game_id ] },
      runoff_opens_at: 8.days.ago, runoff_closes_at: 7.days.ago, runoff_closed_at: 7.days.ago)
    create(:gotm_entry, round_number: 150, game: tied_a)
    a = create(:gotm_nomination, round_number: 150, game: tied_a)
    b = create(:gotm_nomination, round_number: 150, game: tied_b)
    other = create(:gotm_nomination, round_number: 150)
    2.times { create(:gotm_vote, nomination: a) }
    2.times { create(:gotm_vote, nomination: b) }
    create(:gotm_vote, nomination: other)
    2.times { create(:gotm_vote, nomination: a, runoff: true) }
    create(:gotm_vote, nomination: b, runoff: true)

    show(150)

    expect(category).to include("voted" => true, "runoff" => true)
    expect(category.dig("winners", 0, "nomination")).to include("votes" => 2, "runoff_votes" => 2)
    expect(nomination_ids).to eq([ b.nomination_id, other.nomination_id ])
    expect(category.dig("nominations", 0)).to include("votes" => 2, "runoff_votes" => 1)
    expect(category.dig("nominations", 1)).to include("votes" => 1, "runoff_votes" => nil)
    expect(category("nr_gotm")).to include("runoff" => false)
  end

  it "returns a Category with no winner with its Nominations" do
    decided_round(137)
    create(:gotm_entry, round_number: 137, month_year: "July 2025")
    create(:nr_gotm_entry, round_number: 137, month_year: "July 2025", game: create(:game, title: "N/A"))
    nomination = create(:nr_gotm_nomination, round_number: 137)

    show(137)

    expect(category("nr_gotm")).to include("winners" => [])
    expect(nomination_ids("nr_gotm")).to eq([ nomination.nomination_id ])
  end

  it "returns an empty Category when it has neither winners nor Nominations" do
    create(:gotm_entry, round_number: 90, month_year: "May 2020")

    show(90)

    expect(category("nr_gotm")).to include("winners" => [], "nominations" => [], "voted" => false, "runoff" => false)
  end

  it "shows a placeholder nominator as unknown" do
    decided_round(134)
    create(:gotm_entry, round_number: 134)
    nomination = create(:gotm_nomination, round_number: 134, user: nil, user_id: "poll-import-1",
      reason: "From the Discord poll")

    show(134)

    expect(category.dig("nominations", 0)).to include(
      "nomination_id" => nomination.nomination_id, "user" => nil, "reason" => "From the Discord poll"
    )
  end

  it "credits a winner with its game's earliest Nomination and lists the game's others as co-nominations" do
    decided_round(140)
    game = create(:game)
    create(:gotm_entry, round_number: 140, game:)
    credit = create(:gotm_nomination, round_number: 140, game:, reason: "Because", nominated_at: 3.days.ago)
    repeat = create(:gotm_nomination, round_number: 140, game:, reason: "Me too", nominated_at: 1.day.ago)

    show(140)

    expect(category.dig("winners", 0, "nomination")).to include(
      "nomination_id" => credit.nomination_id, "user_id" => credit.user_id, "reason" => "Because"
    )
    expect(category.dig("winners", 0, "nomination", "user")).to include("user_id" => credit.user_id)
    co = category.dig("winners", 0, "nomination", "co_nominations")
    expect(co.length).to eq(1)
    expect(co.first).to include("user_id" => repeat.user_id, "reason" => "Me too")
    expect(co.first.fetch("user")).to include("user_id" => repeat.user_id)
    expect(co.first.fetch("nominated_at")).to be_present
    expect(category.fetch("nominations")).to eq([])
  end

  it "lists a game nominated twice as one row with its votes and runoff votes totalled across both" do
    tied = create(:game)
    twice = create(:game)
    decided_round(151, runoff_ties: { "gotm" => [ tied.game_id, twice.game_id ] },
      runoff_opens_at: 8.days.ago, runoff_closes_at: 7.days.ago, runoff_closed_at: 7.days.ago)
    create(:gotm_entry, round_number: 151, game: tied)
    create(:gotm_nomination, round_number: 151, game: tied, nominated_at: 6.days.ago)
    first = create(:gotm_nomination, round_number: 151, game: twice, nominated_at: 5.days.ago)
    second = create(:gotm_nomination, round_number: 151, game: twice, nominated_at: 4.days.ago, reason: "Again")
    single = create(:gotm_nomination, round_number: 151, nominated_at: 7.days.ago)
    winner = Gotm::RoundDetail::CATEGORIES.fetch("gotm").first.find_by(round_number: 151, gamedb_game_id: tied.game_id)
    3.times { create(:gotm_vote, nomination: winner) }
    2.times { create(:gotm_vote, nomination: first) }
    create(:gotm_vote, nomination: second)
    2.times { create(:gotm_vote, nomination: single) }
    3.times { create(:gotm_vote, nomination: winner, runoff: true) }
    create(:gotm_vote, nomination: first, runoff: true)
    create(:gotm_vote, nomination: second, runoff: true)

    show(151)

    expect(category.dig("winners", 0, "nomination")).to include("votes" => 3, "runoff_votes" => 3, "co_nominations" => [])
    expect(nomination_ids).to eq([ first.nomination_id, single.nomination_id ])
    row = category.dig("nominations", 0)
    expect(row).to include("gamedb_game_id" => twice.game_id, "votes" => 3, "runoff_votes" => 2)
    expect(row.fetch("co_nominations").map { |n| n.fetch("user_id") }).to eq([ second.user_id ])
    expect(row.dig("co_nominations", 0, "reason")).to eq("Again")
    expect(category.dig("nominations", 1)).to include("votes" => 2, "runoff_votes" => nil, "co_nominations" => [])
  end

  it "returns every winner of a round with co-winners in game_index order" do
    decided_round(141)
    first = create(:gotm_entry, round_number: 141, game_index: 0)
    second = create(:gotm_entry, round_number: 141, game_index: 1)
    nomination = create(:gotm_nomination, round_number: 141, game: second.game)

    show(141)

    expect(category.fetch("winners").map { |w| w.fetch("gamedb_game_id") })
      .to eq([ first.gamedb_game_id, second.gamedb_game_id ])
    expect(category.dig("winners", 0, "nomination")).to be_nil
    expect(category.dig("winners", 1, "nomination", "nomination_id")).to eq(nomination.nomination_id)
    expect(category.fetch("nominations")).to eq([])
  end

  it "returns 404 for an unknown round" do
    create(:gotm_entry, round_number: 5)

    show(6)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for a round still taking nominations or votes" do
    create(:voting_round, round_number: 200)
    create(:gotm_nomination, round_number: 200)
    create(:voting_round, round_number: 201, voting_opens_at: 1.day.ago, voting_closes_at: 1.day.from_now)
    create(:gotm_entry, round_number: 201)
    create(:voting_round, round_number: 202, voting_opens_at: 3.days.ago, voting_closes_at: 2.days.ago,
      closed_at: 2.days.ago, runoff_ties: { "gotm" => [ 1, 2 ] }, runoff_opens_at: 2.days.ago,
      runoff_closes_at: 1.day.from_now)
    create(:gotm_entry, round_number: 202)

    [ 200, 201, 202 ].each do |number|
      show(number)
      expect(response).to have_http_status(:not_found), "round #{number}"
    end
  end

  it "returns 404 for a round left tied or closed but not yet decided" do
    create(:voting_round, round_number: 210, voting_opens_at: 3.days.ago, voting_closes_at: 2.days.ago,
      closed_at: 2.days.ago, pending_ties: { "gotm" => [ 1, 2 ] })
    create(:gotm_entry, round_number: 210)
    create(:voting_round, round_number: 211, voting_opens_at: 3.days.ago, voting_closes_at: 2.days.ago)
    create(:gotm_entry, round_number: 211)

    [ 210, 211 ].each do |number|
      show(number)
      expect(response).to have_http_status(:not_found), "round #{number}"
    end
  end

  it "does not link to neighbours that are tied or closed but undecided" do
    create(:voting_round, round_number: 220, voting_opens_at: 3.days.ago, voting_closes_at: 2.days.ago,
      closed_at: 2.days.ago, pending_ties: { "gotm" => [ 1, 2 ] })
    create(:gotm_entry, round_number: 220)
    decided_round(221)
    create(:gotm_entry, round_number: 221)
    create(:voting_round, round_number: 222, voting_opens_at: 3.days.ago, voting_closes_at: 2.days.ago)
    create(:gotm_entry, round_number: 222)

    show(221)

    expect(json.fetch("data")).to include("previous" => nil, "next" => nil)
  end

  it "links the previous and next closed rounds, null at the edges" do
    create(:gotm_entry, round_number: 10)
    create(:nr_gotm_entry, round_number: 12)
    decided_round(15)
    create(:gotm_entry, round_number: 15)
    create(:voting_round, round_number: 16, voting_opens_at: 1.day.ago, voting_closes_at: 1.day.from_now)
    create(:gotm_entry, round_number: 16)

    show(12)
    expect(json.fetch("data")).to include("previous" => 10, "next" => 15)

    show(10)
    expect(json.fetch("data")).to include("previous" => nil, "next" => 12)

    show(15)
    expect(json.fetch("data")).to include("previous" => 12, "next" => nil)
  end

  it "builds the page in a fixed number of queries" do
    queries = lambda do |number|
      count = 0
      callback = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { show(number) }
      expect(response).to have_http_status(:ok)
      count
    end

    [ 160, 161 ].each { |number| decided_round(number) }
    create(:gotm_entry, round_number: 160)
    create(:nr_gotm_entry, round_number: 160)
    small = create(:gotm_nomination, round_number: 160)
    create(:nr_gotm_nomination, round_number: 160)
    create(:gotm_vote, nomination: small)

    create(:gotm_entry, round_number: 161, game_index: 0)
    create(:gotm_entry, round_number: 161, game_index: 1)
    create_list(:nr_gotm_entry, 1, round_number: 161)
    noms = create_list(:gotm_nomination, 4, round_number: 161)
    create_list(:nr_gotm_nomination, 3, round_number: 161)
    noms.each { |nomination| create_list(:gotm_vote, 2, nomination:) }
    create(:gotm_vote, nomination: noms.first, runoff: true)
    create(:discord_thread).then { |thread| create(:thread_game_link, thread:, game: noms.first.game) }

    queries.call(160)
    expect(queries.call(161)).to eq(queries.call(160))
  end

  it "requires authentication" do
    create(:gotm_entry, round_number: 3)

    get "/api/v1/gotm_rounds/3"

    expect(response).to have_http_status(:unauthorized)
  end
end

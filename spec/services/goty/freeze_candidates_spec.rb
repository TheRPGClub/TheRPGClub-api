# frozen_string_literal: true

require "rails_helper"

# Freezing each Award's candidates when voting opens (spec api#471, ticket
# api#474).
RSpec.describe Goty::FreezeCandidates do
  let(:base) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }
  let!(:vote) { create(:goty_vote, year: 2026) }
  let(:voting) { vote.voting_opens_at + 1.minute }

  def candidates(award)
    GotyCandidate.ballot(2026, award).pluck(:gamedb_game_id)
  end

  def nominate(game)
    create(:goty_nomination, year: 2026, game: game)
  end

  it "writes the round winners and the eligible nominated games, in ballot order" do
    gotm_a, gotm_b, nr = create_list(:game, 3)
    create(:gotm_entry, round_number: base, month_year: "March 2026", game_index: 0, game: gotm_a)
    create(:gotm_entry, round_number: base + 1, month_year: "April 2026", game: gotm_b)
    create(:nr_gotm_entry, round_number: base, month_year: "March 2026", game: nr)
    first = create(:game, initial_release_date: Time.utc(2026, 3, 1))
    second = create(:game, initial_release_date: Time.utc(2026, 8, 1))
    nominate(first)
    nominate(second)
    nominate(first)

    expect(described_class.call(vote, now: voting)).to be(true)

    expect(candidates("gotm")).to eq([ gotm_a.game_id, gotm_b.game_id ])
    expect(candidates("nr_gotm")).to eq([ nr.game_id ])
    expect(candidates("game_of_the_year")).to eq([ first.game_id, second.game_id ])
    expect(vote.reload.candidates_frozen_at).to eq(voting)
  end

  it "drops a nominated game that is no longer eligible" do
    kept = create(:game, initial_release_date: Time.utc(2026, 3, 1))
    corrected = create(:game, initial_release_date: Time.utc(2026, 3, 1))
    nominate(kept)
    nominate(corrected)
    corrected.update!(initial_release_date: Time.utc(2025, 11, 1))

    described_class.call(vote, now: voting)

    expect(candidates("game_of_the_year")).to eq([ kept.game_id ])
  end

  it "is idempotent: a second freeze changes nothing" do
    game = create(:game)
    create(:gotm_entry, round_number: base, month_year: "May 2026", game: game)
    described_class.call(vote, now: voting)
    create(:gotm_entry, round_number: base + 1, month_year: "June 2026", game: create(:game))

    expect(described_class.call(vote, now: voting + 1.hour)).to be(false)

    expect(candidates("gotm")).to eq([ game.game_id ])
  end

  it "does nothing before voting opens" do
    create(:gotm_entry, round_number: base, month_year: "May 2026", game: create(:game))

    expect(described_class.call(vote, now: vote.voting_opens_at - 1.minute)).to be(false)

    expect(GotyCandidate.where(year: 2026)).to be_empty
    expect(vote.reload.candidates_frozen_at).to be_nil
  end
end

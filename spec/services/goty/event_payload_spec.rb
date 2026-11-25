# frozen_string_literal: true

require "rails_helper"

# The goty_* outbox payload (spec api#471, ticket api#479: where each GOTM /
# NR-GOTM of the Year game won).
RSpec.describe Goty::EventPayload do
  let(:base) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }

  def award(data, key)
    data.fetch(:awards).find { |row| row[:award] == key }
  end

  it "says where each GOTM / NR-GOTM of the Year game won, before and after the freeze" do
    twice, nr, nominated = create_list(:game, 3)
    create(:gotm_entry, round_number: base, month_year: "January 2026", game: twice)
    create(:gotm_entry, round_number: base + 2, month_year: "March 2026", game: twice)
    create(:nr_gotm_entry, round_number: base + 1, month_year: "February 2026", game: nr)
    vote = create(:goty_vote, year: 2026)
    create(:goty_nomination, year: 2026, game: nominated)
    expected = [ { round_number: base, month_year: "January 2026" },
                 { round_number: base + 2, month_year: "March 2026" } ]

    live = described_class.for(vote, "goty_nominations_opened")
    expect(award(live, "gotm")[:games].first).to include(gamedb_game_id: twice.game_id, won_in: expected)
    expect(award(live, "nr_gotm")[:games].first)
      .to include(won_in: [ { round_number: base + 1, month_year: "February 2026" } ])
    expect(award(live, "game_of_the_year")[:games].first).not_to have_key(:won_in)

    Goty::FreezeCandidates.call(vote, now: vote.voting_opens_at)
    frozen = described_class.for(vote.reload, "goty_voting_opened")
    expect(award(frozen, "gotm")[:games].first).to include(gamedb_game_id: twice.game_id, won_in: expected)
  end
end

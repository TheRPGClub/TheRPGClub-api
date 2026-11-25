# frozen_string_literal: true

require "rails_helper"

# The GOTM and NR-GOTM of the Year ballots, built live from the year's round
# winners (spec api#471).
RSpec.describe Goty::Ballots do
  let(:base) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }

  describe ".round_year" do
    it "reads the year of a month label, including older formats" do
      expect(described_class.round_year("March 2026")).to eq(2026)
      expect(described_class.round_year(" march 2026 ")).to eq(2026)
      expect(described_class.round_year("Mar 2026")).to eq(2026)
      expect(described_class.round_year("2026-03")).to eq(2026)
      expect(described_class.round_year("03/2026")).to eq(2026)
    end

    it "is nil for a label with no year" do
      expect(described_class.round_year("March")).to be_nil
      expect(described_class.round_year(nil)).to be_nil
      expect(described_class.round_year("Round 12345")).to be_nil
    end
  end

  describe ".for" do
    it "puts every winner of a multi-winner round on the ballot, in round order" do
      first, second, third = create_list(:game, 3)
      create(:gotm_entry, round_number: base, month_year: "February 2026", game_index: 0, game: first)
      create(:gotm_entry, round_number: base, month_year: "February 2026", game_index: 1, game: second)
      create(:gotm_entry, round_number: base + 1, month_year: "March 2026", game_index: 0, game: third)

      expect(described_class.for(2026).fetch("gotm")).to eq([ first.game_id, second.game_id, third.game_id ])
    end

    it "lists a game that won twice in the year once" do
      game, other = create_list(:game, 2)
      create(:nr_gotm_entry, round_number: base, month_year: "April 2026", game: game)
      create(:nr_gotm_entry, round_number: base + 1, month_year: "May 2026", game: other)
      create(:nr_gotm_entry, round_number: base + 2, month_year: "June 2026", game: game)

      expect(described_class.for(2026).fetch("nr_gotm")).to eq([ game.game_id, other.game_id ])
    end

    it "counts a round toward the year in its label, legacy formats included, and no other year" do
      legacy, current, last_year, next_year = create_list(:game, 4)
      create(:gotm_entry, round_number: base, month_year: "Jan 2026", game: legacy)
      create(:gotm_entry, round_number: base + 1, month_year: "December 2026", game: current)
      create(:gotm_entry, round_number: base - 1, month_year: "December 2025", game: last_year)
      create(:gotm_entry, round_number: base + 2, month_year: "January 2027", game: next_year)

      expect(described_class.for(2026).fetch("gotm")).to eq([ legacy.game_id, current.game_id ])
    end

    it "leaves out NR-GOTM placeholder games and entries with no game" do
      placeholder = create(:game, title: "N/A")
      create(:nr_gotm_entry, round_number: base, month_year: "July 2026", game: placeholder)
      build(:nr_gotm_entry, round_number: base + 1, month_year: "August 2026", game: nil).save!(validate: false)

      expect(described_class.for(2026).fetch("nr_gotm")).to eq([])
    end

    it "keeps the Awards apart and leaves Game of the Year empty until nominations land" do
      gotm, nr = create_list(:game, 2)
      create(:gotm_entry, round_number: base, month_year: "May 2026", game: gotm)
      create(:nr_gotm_entry, round_number: base, month_year: "May 2026", game: nr)

      expect(described_class.for(2026)).to eq(
        "gotm" => [ gotm.game_id ], "nr_gotm" => [ nr.game_id ], "game_of_the_year" => []
      )
    end
  end
end

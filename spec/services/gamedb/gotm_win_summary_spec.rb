# frozen_string_literal: true

require 'rails_helper'

# Behavioral coverage for the in-memory ordering/latest-value derivation
# GamesController#profile relies on to avoid re-querying gotm_entries /
# nr_gotm_entries (#117, PR #197) -- the request specs are rswag doc-only and
# never exercise it. Runs against the real test database with plain
# ActiveRecord setup, matching the repo's no-fixtures/no-factories stance.
RSpec.describe Gamedb::GotmWinSummary do
  let(:game) { GamedbGame.create!(title: "Game A") }

  def create_entry!(round_number:, month_year:, game_index: 1)
    GotmEntry.create!(gamedb_game_id: game.game_id, round_number: round_number, month_year: month_year, game_index: game_index)
  end

  it "orders entries ascending by round_number regardless of insertion or query order" do
    later = create_entry!(round_number: 5, month_year: "2024-05")
    earlier = create_entry!(round_number: 2, month_year: "2024-02")
    middle = create_entry!(round_number: 3, month_year: "2024-03")

    summary = described_class.new([ later, earlier, middle ])

    expect(summary.ordered).to eq([ earlier, middle, later ])
  end

  it "resolves the latest month_year as the highest round_number's value" do
    create_entry!(round_number: 2, month_year: "2024-02")
    create_entry!(round_number: 5, month_year: "2024-05")

    summary = described_class.new(game.gotm_entries)

    expect(summary.latest_month_year).to eq("2024-05")
  end

  it "returns nil for an empty entry set" do
    summary = described_class.new([])

    expect(summary.ordered).to eq([])
    expect(summary.latest_month_year).to be_nil
  end
end

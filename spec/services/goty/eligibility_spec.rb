# frozen_string_literal: true

require "rails_helper"

# Game of the Year eligibility (spec api#471): a game is eligible for year Y
# when its earliest dated Release, anywhere, falls in Y.
RSpec.describe Goty::Eligibility do
  let(:game) { create(:game) }

  def release(date, precision: "day", source: "igdb", of: game)
    create(:release, game: of, release_date: date, date_precision: precision, source: source)
  end

  it "judges a game by the earliest of several Releases" do
    release(Date.new(2026, 3, 5))
    release(Date.new(2025, 11, 20)) # an earlier region
    release(Date.new(2026, 1, 9))

    result = described_class.check(game, 2026)

    expect(result).not_to be_eligible
    expect(result.reason).to eq("not_released_in_year")
    expect(result.released_on).to eq(Date.new(2025, 11, 20))
    expect(described_class.check(game, 2025)).to be_eligible
  end

  it "counts a Release known only to the year" do
    release(Date.new(2026, 1, 1), precision: "year")

    result = described_class.check(game, 2026)

    expect(result).to be_eligible
    expect(result.reason).to be_nil
    expect(result.date_precision).to eq("year")
  end

  it "counts a Manual Release like an IGDB one" do
    release(Date.new(2026, 6, 1), source: "manual")
    release(Date.new(2027, 2, 1), source: "igdb")

    expect(described_class.check(game, 2026)).to be_eligible
  end

  it "ignores TBA Releases" do
    create(:release, game: game, release_date: nil, date_precision: "tba")
    release(Date.new(2026, 8, 14))

    expect(described_class.check(game, 2026)).to be_eligible
  end

  it "judges a remake by its own Releases, not its original's" do
    remake = create(:game)
    low, high = [ game, remake ].sort_by(&:game_id)
    GamedbGameAlternate.create!(game: low, alternate_game: high)
    release(Date.new(1998, 7, 1))
    release(Date.new(2026, 2, 27), of: remake)

    expect(described_class.check(remake, 2026)).to be_eligible
    expect(described_class.check(game, 2026)).not_to be_eligible
  end

  it "falls back to the initial release date when there are no dated Releases" do
    game.update!(initial_release_date: Time.utc(2026, 10, 10))
    create(:release, game: game, release_date: nil, date_precision: "tba")

    result = described_class.check(game, 2026)

    expect(result).to be_eligible
    expect(result.released_on).to eq(Date.new(2026, 10, 10))
    expect(result.source).to eq("initial_release_date")
  end

  it "prefers the Releases over the initial release date" do
    game.update!(initial_release_date: Time.utc(2026, 10, 10))
    release(Date.new(2025, 12, 1))

    expect(described_class.check(game, 2026).reason).to eq("not_released_in_year")
  end

  it "is release_unknown with neither" do
    result = described_class.check(game, 2026)

    expect(result).not_to be_eligible
    expect(result.reason).to eq("release_unknown")
    expect(result.released_on).to be_nil
  end
end

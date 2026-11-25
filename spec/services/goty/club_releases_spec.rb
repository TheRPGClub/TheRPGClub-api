# frozen_string_literal: true

require "rails_helper"

# The Year So Far's club releases (spec api#481). The request specs cover
# what counts; this covers the brief cache that spares the UNION on every
# upcoming render.
RSpec.describe Goty::ClubReleases do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:game) { create(:game, title: "Played", initial_release_date: Time.utc(2026, 6, 1)) }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    create(:completion, game: game)
  end

  def played_queries
    queries = 0
    callback = ->(*, payload) { queries += 1 if payload[:name] == "Goty::ClubReleases" }
    rows = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.for(2026) }
    [ rows.map { |row| [ row.game.title, row.members_played ] }, queries ]
  end

  it "runs the played query once per year within the cache window" do
    expect(played_queries).to eq([ [ [ "Played", 1 ] ], 1 ])

    create(:completion, game: game)
    expect(played_queries).to eq([ [ [ "Played", 1 ] ], 0 ])
  end

  it "counts again once the cache window has passed" do
    played_queries
    create(:completion, game: game)

    travel(described_class::CACHE_FOR + 1.second) do
      expect(played_queries).to eq([ [ [ "Played", 2 ] ], 1 ])
    end
  end
end

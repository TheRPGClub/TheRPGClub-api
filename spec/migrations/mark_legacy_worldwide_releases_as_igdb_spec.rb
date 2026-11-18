# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118100000_mark_legacy_worldwide_releases_as_igdb.rb")

# api#389 owner decision (review-api #1): before the region fix every IGDB
# import stored its Releases as Worldwide, and api#390 turned them all into
# Manual Releases, so a refresh never adopted them. Importer-shaped Worldwide
# Releases of a game with an IGDB id become IGDB Releases, so the next refresh
# replaces them with IGDB's regional Releases.
RSpec.describe MarkLegacyWorldwideReleasesAsIgdb do
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  let(:worldwide) { GamedbRegion.create_with(region_name: "Worldwide").find_or_create_by!(region_code: "WW") }
  let(:igdb_game) { create(:game, igdb_id: SecureRandom.random_number(1_000_000_000)) }

  it "marks an importer-shaped Worldwide Release of an IGDB game as an IGDB Release" do
    legacy = create(:release, game: igdb_game, region: worldwide, release_date: Date.new(2027, 3, 10))
    undated = create(:release, game: igdb_game, region: worldwide, release_date: nil)

    migrate(:up)

    expect(legacy.reload).to be_source_igdb
    expect(undated.reload).to be_source_igdb
  end

  it "keeps Completionator Releases (with notes) and staff Releases (with a format) Manual" do
    completionator = create(:release, game: igdb_game, region: worldwide, release_date: Date.new(2027, 3, 10),
      notes: "Imported from Completionator")
    staff = create(:release, game: igdb_game, region: worldwide, release_date: Date.new(2027, 3, 10),
      format: "Physical")

    migrate(:up)

    expect(completionator.reload).to be_source_manual
    expect(staff.reload).to be_source_manual
  end

  it "keeps Releases outside Worldwide, and those of a game with no IGDB id, Manual" do
    regional = create(:release, game: igdb_game, region: create(:region), release_date: Date.new(2027, 3, 10))
    no_igdb = create(:release, game: create(:game), region: worldwide, release_date: Date.new(2027, 3, 10))

    migrate(:up)

    expect(regional.reload).to be_source_manual
    expect(no_igdb.reload).to be_source_manual
  end

  it "leaves every Release as it is when rolled back" do
    create(:release, game: igdb_game, region: worldwide, release_date: Date.new(2027, 3, 10))
    migrate(:up)

    expect { migrate(:down) }.not_to(change { GamedbRelease.order(:release_id).pluck(:release_id, :source) })
  end
end

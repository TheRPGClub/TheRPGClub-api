# frozen_string_literal: true

require "rails_helper"

# Behavioral coverage for the two game.touch fixes (#154 review): both
# refresh_releases! and upsert_game! can insert child rows (releases, taxonomy
# joins) without the game's own columns changing, in which case `save!` alone
# would not advance updated_at -- and GamesController#relations_data's cache is
# keyed on it. Runs against the real test database with plain ActiveRecord
# setup (no fixtures/factories), matching this repo's precedent for
# service-level behavioral specs (spec/services/voting/cast_vote_spec.rb);
# the controllers that also call into these paths stay doc-only.
RSpec.describe Gamedb::IgdbGameImporter do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  let(:image_importer) { instance_double(Gamedb::IgdbImageImporter, import!: []) }
  let(:client) { instance_double(Igdb::Client) }
  subject(:importer) { described_class.new(client: client, image_importer: image_importer) }

  def base_payload(igdb_id:, genres: [])
    {
      igdb_id: igdb_id,
      name: "Game A",
      slug: "game-a",
      summary: "A game.",
      url: "https://igdb.example/game-a",
      total_rating: 80.0,
      first_release_date: nil,
      parent_igdb_id: nil,
      parent_game_name: nil,
      collection: nil,
      genres: genres,
      themes: [],
      perspectives: [],
      game_modes: [],
      engines: [],
      franchises: [],
      platforms: [],
      companies: [],
      release_dates: []
    }
  end

  describe "#import! (upsert_game!)" do
    it "bumps updated_at when a re-import adds a taxonomy join even though the game's own columns are unchanged" do
      igdb_id = 601
      allow(client).to receive(:game).and_return(
        base_payload(igdb_id: igdb_id, genres: [ { igdb_id: 10, name: "RPG" } ]),
        base_payload(igdb_id: igdb_id, genres: [ { igdb_id: 10, name: "RPG" }, { igdb_id: 11, name: "Action" } ])
      )

      result = importer.import!(igdb_id)
      original_updated_at = result.game.updated_at
      expect(result.game.genres.count).to eq(1)

      travel 1.second
      second_result = importer.import!(igdb_id)

      expect(second_result.game.game_id).to eq(result.game.game_id)
      expect(second_result.game.genres.count).to eq(2)
      expect(second_result.game.updated_at).to be > original_updated_at
    end
  end

  describe "#refresh_releases!" do
    it "bumps the game's updated_at after rebuilding its release rows" do
      game = GamedbGame.create!(title: "Game A", igdb_id: 602)
      original_updated_at = game.updated_at

      allow(client).to receive(:game).with(game.igdb_id).and_return(
        release_dates: [
          { region: 8, platform: { igdb_id: 77, name: "PC" }, date: Time.zone.parse("2020-01-01") }
        ]
      )

      travel 1.second
      refreshed = importer.refresh_releases!(game.game_id)

      expect(refreshed.releases.count).to eq(1)
      expect(refreshed.updated_at).to be > original_updated_at
    end

    it "still bumps updated_at when the refreshed release set is empty" do
      game = GamedbGame.create!(title: "Game A", igdb_id: 603)
      original_updated_at = game.updated_at

      allow(client).to receive(:game).with(game.igdb_id).and_return(release_dates: [])

      travel 1.second
      refreshed = importer.refresh_releases!(game.game_id)

      expect(refreshed.releases.count).to eq(0)
      expect(refreshed.updated_at).to be > original_updated_at
    end
  end
end

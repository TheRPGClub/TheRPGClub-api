# frozen_string_literal: true

require "rails_helper"

# Behavioral coverage for the game.touch fix (#154 review): images live on a
# child table (gamedb_game_images), so import! must bump the game's
# updated_at itself -- otherwise GamesController#relations_data's cache (keyed
# on updated_at) would keep rendering a stale cover/art/logo URL for this game
# wherever it appears in another game's cached `alternates` list.
RSpec.describe Gamedb::IgdbImageImporter do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  let(:game) { GamedbGame.create!(title: "Game A", igdb_id: 555) }
  let(:fake_image) { instance_double(GamedbGameImage, kind: "cover", image_id: 1) }
  let(:storage) { instance_double(Gamedb::GameImageStorage, import_igdb!: fake_image, delete!: true) }
  let(:client) { instance_double(Igdb::Client, game_images: { cover_image_id: 123, artworks: [] }) }
  subject(:importer) { described_class.new(client: client, storage: storage) }

  it "bumps the game's updated_at on a successful import" do
    original_updated_at = game.updated_at
    travel 1.second

    importer.import!(game)

    expect(game.reload.updated_at).to be > original_updated_at
  end
end

# frozen_string_literal: true

require "rails_helper"

# Behavioral coverage for the Gamedb::GameRelationsCacheVersion bump fix
# (#154 review): images live on a child table (gamedb_game_images), and
# relations_data never renders this game's own image URLs -- only another
# game's cached `alternates` slice does (via GameResource). import! must bump
# the shared version so those other caches invalidate.
RSpec.describe Gamedb::IgdbImageImporter do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  let(:game) { GamedbGame.create!(title: "Game A", igdb_id: 555) }
  let(:fake_image) { instance_double(GamedbGameImage, kind: "cover", image_id: 1) }
  let(:storage) { instance_double(Gamedb::GameImageStorage, import_igdb!: fake_image, delete!: true) }
  let(:client) { instance_double(Igdb::Client, game_images: { cover_image_id: 123, artworks: [] }) }
  subject(:importer) { described_class.new(client: client, storage: storage) }

  it "bumps the shared relations-cache version on a successful import" do
    original_version = Gamedb::GameRelationsCacheVersion.current

    importer.import!(game)

    expect(Gamedb::GameRelationsCacheVersion.current).to eq(original_version + 1)
  end
end

# frozen_string_literal: true

require "rails_helper"

# The owner-safe "GameDB game from an IGDB id" path for import items (the
# bot's importGameFromIgdb, minus the admin-only POST /games). It reuses
# Gamedb::IgdbGameImporter and turns its failures into error codes an item
# endpoint can render.
RSpec.describe Imports::IgdbGameResolver do
  subject(:resolver) { described_class.new(importer: importer) }

  let(:importer) { instance_double(Gamedb::IgdbGameImporter) }
  let(:igdb_id) { SecureRandom.random_number(1_000_000_000) }

  it "returns the existing game without calling IGDB" do
    game = create(:game, igdb_id: igdb_id)
    allow(importer).to receive(:import!)

    result = resolver.resolve(igdb_id)

    expect(result).to have_attributes(game: game, created: false, error: nil)
    expect(result).to be_ok
    expect(importer).not_to have_received(:import!)
  end

  it "imports a game IGDB knows but GameDB does not" do
    game = create(:game)
    allow(importer).to receive(:import!).with(igdb_id)
      .and_return(Gamedb::IgdbGameImporter::Result.new(game: game, created: true, images: []))

    expect(resolver.resolve(igdb_id.to_s)).to have_attributes(game: game, created: true, error: nil)
  end

  it "rejects an id that is not a positive integer" do
    expect(resolver.resolve("abc")).to have_attributes(game: nil, error: "invalid_igdb_id")
    expect(resolver.resolve(0)).to have_attributes(game: nil, error: "invalid_igdb_id")
  end

  it "reports an IGDB id that IGDB does not know" do
    allow(importer).to receive(:import!).and_raise(Gamedb::IgdbGameImporter::MissingIgdbGameError)

    result = resolver.resolve(igdb_id)

    expect(result).to have_attributes(game: nil, error: "igdb_game_not_found")
    expect(result).not_to be_ok
  end

  it "reports IGDB configuration and request failures" do
    allow(importer).to receive(:import!).and_raise(Igdb::Client::ConfigurationError)
    expect(resolver.resolve(igdb_id).error).to eq("igdb_not_configured")

    allow(importer).to receive(:import!).and_raise(Igdb::Client::RequestError)
    expect(resolver.resolve(igdb_id).error).to eq("igdb_request_failed")
  end

  it "keeps the imported game when only its images fail" do
    game = create(:game)
    allow(importer).to receive(:import!) do
      game.update!(igdb_id: igdb_id)
      raise Backblaze::Client::RequestError, "upload failed"
    end

    expect(resolver.resolve(igdb_id)).to have_attributes(game: game, created: true, error: nil)
  end
end

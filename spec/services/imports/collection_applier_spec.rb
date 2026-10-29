# frozen_string_literal: true

require "rails_helper"

# The collection write shared by the Steam and collection CSV imports (the
# bot's applySteamImportSelection / applyCsvImportSelection outcome ladder):
# added, added with platform_unresolved, skipped/duplicate (from the
# uq_user_game_collections_dedup RecordNotUnique), or failed/add_failed.
RSpec.describe Imports::CollectionApplier do
  subject(:applier) { described_class.new(user_id: user.user_id) }

  let(:user) { create(:user) }
  let(:game) { create(:game) }
  let(:platform) { create(:platform) }

  describe "#apply" do
    it "adds a collection entry" do
      result = applier.apply(game_id: game.game_id, platform_id: platform.platform_id, ownership_type: "Physical", note: "boxed")

      expect(result).to have_attributes(status: "added", reason: nil, error: nil)
      expect(result).to be_added
      expect(result.entry).to have_attributes(
        user_id: user.user_id, gamedb_game_id: game.game_id, platform_id: platform.platform_id,
        ownership_type: "Physical", note: "boxed"
      )
      expect(result.entry).to be_persisted
    end

    it "defaults to a Digital entry without a platform" do
      result = applier.apply(game_id: game.game_id)

      expect(result.entry).to have_attributes(ownership_type: "Digital", platform_id: nil)
    end

    it "flags an added entry whose platform could not be resolved" do
      result = applier.apply(game_id: game.game_id, platform_id: nil, platform_unresolved: true)

      expect(result).to have_attributes(status: "added", reason: "platform_unresolved")
    end

    it "skips a duplicate entry and leaves the transaction usable" do
      create(:collection_entry, user: user, game: game, platform: platform, ownership_type: "Digital")

      result = applier.apply(game_id: game.game_id, platform_id: platform.platform_id)

      expect(result).to have_attributes(status: "skipped", reason: "duplicate", entry: nil)
      expect(result).to be_skipped
      expect(UserGameCollection.where(user_id: user.user_id).count).to eq(1)
    end

    it "fails when the game does not exist" do
      result = applier.apply(game_id: (GamedbGame.maximum(:game_id) || 0) + 1_000)

      expect(result).to have_attributes(status: "failed", reason: "add_failed", entry: nil)
      expect(result).to be_failed
      expect(result.error).to be_present
      expect(UserGameCollection.where(user_id: user.user_id).count).to eq(0)
    end

    it "fails on an unknown ownership type" do
      result = applier.apply(game_id: game.game_id, ownership_type: "Borrowed")

      expect(result).to have_attributes(status: "failed", reason: "add_failed")
      expect(result.error).to include("ownership")
    end
  end

  describe ".normalize_ownership" do
    it "matches the allowed values case-insensitively" do
      expect(described_class.normalize_ownership(" physical ")).to eq("Physical")
    end

    it "defaults a blank value to Digital" do
      expect(described_class.normalize_ownership(nil)).to eq("Digital")
      expect(described_class.normalize_ownership("")).to eq("Digital")
    end

    it "returns nil for an unknown value" do
      expect(described_class.normalize_ownership("Borrowed")).to be_nil
    end
  end
end

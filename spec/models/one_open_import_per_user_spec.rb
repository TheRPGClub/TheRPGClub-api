# frozen_string_literal: true

require "rails_helper"

# One active or paused import per user per import kind (web-parity #287).
# The bot only checked GET .../active before starting; the rule now lives on
# the three import models so every create path (bot and web) is covered.
RSpec.describe OneOpenImportPerUser do
  {
    steam_collection_import: RpgClubSteamCollectionImport,
    collection_csv_import: RpgClubCollectionCsvImport,
    completionator_import: RpgClubCompletionatorImport
  }.each do |factory, model|
    describe model do
      let(:user) { create(:user) }

      %w[active paused].each do |open_status|
        it "refuses a second import while one is #{open_status}" do
          create(factory, user: user, status: open_status)

          second = build(factory, user: user, status: "active")

          expect(second).not_to be_valid
          expect(second.errors[:base]).to include("user already has an active or paused import")
        end
      end

      it "allows a new import once the previous one is finished" do
        create(factory, user: user, status: "completed")
        create(factory, user: user, status: "canceled")

        expect(build(factory, user: user, status: "active")).to be_valid
      end

      it "does not count other users' imports" do
        create(factory, status: "active")

        expect(build(factory, user: user, status: "active")).to be_valid
      end

      it "does not count other import kinds" do
        other = (%i[steam_collection_import collection_csv_import completionator_import] - [ factory ]).first
        create(other, user: user, status: "active")

        expect(build(factory, user: user, status: "active")).to be_valid
      end

      it "lets the open import move between active and paused" do
        import = create(factory, user: user, status: "active")

        expect(import.update(status: "paused")).to be(true)
        expect(import.update(status: "active", current_index: 3)).to be(true)
      end

      it "refuses to reopen a finished import while another is open" do
        finished = create(factory, user: user, status: "canceled")
        create(factory, user: user, status: "paused")

        expect(finished.update(status: "active")).to be(false)
      end

      it "still lets legacy duplicate open imports be updated" do
        create(factory, user: user, status: "active")
        legacy = build(factory, user: user, status: "paused").tap { |record| record.save!(validate: false) }

        expect(legacy.update(current_index: 4, status: "active")).to be(true)
      end

      it "exposes the open imports through .open_for_user" do
        open_import = create(factory, user: user, status: "paused")
        create(factory, user: user, status: "completed")

        expect(model.open_for_user(user.user_id)).to contain_exactly(open_import)
      end
    end
  end
end

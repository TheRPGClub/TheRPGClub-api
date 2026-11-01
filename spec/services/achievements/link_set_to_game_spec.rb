# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::LinkSetToGame do
  describe ".call" do
    it "links a Steam Achievement Set through the Steam app map" do
      game = create(:game, title: "Hades")
      set = create(:achievement_set, provider: "steam", external_id: "1145360", title: "Unrelated Steam Title")
      create(:steam_app_gamedb_map, steam_app_id: 1_145_360, gamedb_game_id: game.game_id, status: "mapped")

      described_class.call(set)

      expect(set.reload.game_id).to eq(game.game_id)
    end

    it "links a RetroAchievements set to the single exact GameDB title match" do
      title = "Chrono Trigger #{SecureRandom.hex(3)}"
      game = create(:game, title: title)
      create(:game, title: "#{title}: Director's Commentary")
      set = create(:achievement_set, provider: "retroachievements", external_id: "319", title: title)

      described_class.call(set)

      expect(set.reload.game_id).to eq(game.game_id)
    end
    it "links a PSN set through its title without edition noise" do
      title = "Sleeping Dogs #{SecureRandom.hex(3)}"
      game = create(:game, title: title)
      set = create(:achievement_set, provider: "psn", external_id: "NPWR0#{SecureRandom.hex(3)}",
        title: "#{title}™: Definitive Edition")

      described_class.call(set)

      expect(set.reload.game_id).to eq(game.game_id)
    end

    it "leaves an ambiguous title match unlinked" do
      title = "Doom #{SecureRandom.hex(3)}"
      create(:game, title: title)
      create(:game, title: "#{title} (2016)")
      set = create(:achievement_set, provider: "retroachievements", external_id: "1", title: title)

      described_class.call(set)

      expect(set.reload.game_id).to be_nil
    end

    it "leaves a set with no GameDB match unlinked" do
      set = create(:achievement_set, provider: "psn", title: "No Such Game #{SecureRandom.hex(6)}")

      described_class.call(set)

      expect(set.reload.game_id).to be_nil
    end

    it "never overwrites an existing link" do
      title = "Okami #{SecureRandom.hex(3)}"
      create(:game, title: title)
      manual = create(:game, title: "Manually Chosen #{SecureRandom.hex(3)}")
      set = create(:achievement_set, provider: "psn", title: title, game_id: manual.game_id)

      described_class.call(set)

      expect(set.reload.game_id).to eq(manual.game_id)
    end

    it "keeps a Steam set unlinked when the Steam app map says skipped" do
      title = "Portal #{SecureRandom.hex(3)}"
      create(:game, title: title)
      set = create(:achievement_set, provider: "steam", external_id: "400", title: title)
      create(:steam_app_gamedb_map, steam_app_id: 400, status: "skipped")

      described_class.call(set)

      expect(set.reload.game_id).to be_nil
    end

    it "ignores a Steam app map row whose GameDB game is gone" do
      set = create(:achievement_set, provider: "steam", title: "No Such Game #{SecureRandom.hex(6)}")
      create(:steam_app_gamedb_map, steam_app_id: set.external_id.to_i, gamedb_game_id: 2_000_000_000, status: "mapped")

      expect { described_class.call(set) }.not_to raise_error
      expect(set.reload.game_id).to be_nil
    end

    it "falls back to title matching for a Steam app with no map row" do
      title = "Celeste #{SecureRandom.hex(3)}"
      game = create(:game, title: title)
      set = create(:achievement_set, provider: "steam", title: title)

      described_class.call(set)

      expect(set.reload.game_id).to eq(game.game_id)
    end
  end

  describe ".link_unlinked" do
    it "relinks only unlinked sets and returns how many it linked" do
      title = "Ico #{SecureRandom.hex(3)}"
      game = create(:game, title: title)
      unlinked = create(:achievement_set, provider: "psn", title: title)
      manual = create(:game, title: "Manually Chosen #{SecureRandom.hex(3)}")
      linked = create(:achievement_set, provider: "psn", title: title, game_id: manual.game_id)
      create(:achievement_set, provider: "psn", title: "No Such Game #{SecureRandom.hex(6)}")

      expect(described_class.link_unlinked).to eq(1)
      expect(unlinked.reload.game_id).to eq(game.game_id)
      expect(linked.reload.game_id).to eq(manual.game_id)
    end
  end
end

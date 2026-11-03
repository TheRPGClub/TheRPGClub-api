# frozen_string_literal: true

require "rails_helper"

RSpec.describe Imports::UniqueTitleMatch do
  describe ".call" do
    it "matches the single exact GameDB title, ignoring case and punctuation" do
      title = "Chrono Trigger #{SecureRandom.hex(3)}"
      game = create(:game, title: title)
      create(:game, title: "#{title}: Director's Commentary")

      result = described_class.call("  #{title.upcase}! ")

      expect(result).to be_matched
      expect(result.game_id).to eq(game.game_id)
    end

    it "falls back to the title without edition noise" do
      title = "Sleeping Dogs #{SecureRandom.hex(3)}"
      game = create(:game, title: title)

      expect(described_class.call("#{title}: Definitive Edition").game_id).to eq(game.game_id)
    end

    it "is ambiguous when several games match exactly" do
      title = "Doom #{SecureRandom.hex(3)}"
      create(:game, title: title)
      create(:game, title: "#{title}!")

      result = described_class.call(title)

      expect(result).to be_ambiguous
      expect(result.game_id).to be_nil
    end

    it "does not fall back to the edition-free title when the full title is ambiguous" do
      title = "Okami #{SecureRandom.hex(3)}"
      create(:game, title: "#{title} HD")
      create(:game, title: "#{title} HD!")
      create(:game, title: title)

      expect(described_class.call("#{title} HD")).to be_ambiguous
    end

    it "is none when no game matches, or the title is blank" do
      create(:game, title: "Something Else #{SecureRandom.hex(3)}")

      expect(described_class.call("No Such Game #{SecureRandom.hex(6)}").status).to eq(:none)
      expect(described_class.call("  ").status).to eq(:none)
      expect(described_class.call(nil).status).to eq(:none)
    end
  end
end

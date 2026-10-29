# frozen_string_literal: true

require "rails_helper"

# Fixtures ported from the bot's ImportTitleNormalization.ts behaviour: the
# seven cumulative ignore steps, the progressive variant list (raw title plus
# one entry per cumulative step, deduped) and the exact-match check.
RSpec.describe Imports::TitleNormalizer do
  describe ".normalize" do
    it "applies every ignore step cumulatively" do
      expect(described_class.normalize("The Legend of Zelda: Breath of the Wild (2017)"))
        .to eq("Legend of Zelda Breath of Wild")
    end

    it "strips dated suffixes, trademark marks and dashes" do
      expect(described_class.normalize("Halo™ — Combat Evolved (2001-11-15)")).to eq("Halo Combat Evolved")
    end

    it "keeps apostrophes and turns other punctuation into spaces" do
      expect(described_class.normalize("Baldur's Gate!! II & More")).to eq("Baldur's Gate II More")
    end

    it "keeps non-latin letters and digits" do
      expect(described_class.normalize("ファイナルファンタジー 7")).to eq("ファイナルファンタジー 7")
    end

    it "applies only the first step_count steps" do
      expect(described_class.normalize("The Witcher: Wild Hunt (2015)", step_count: 1)).to eq("The Witcher: Wild Hunt")
    end
  end

  describe ".progressive_variants" do
    it "returns the raw title followed by each new cumulative step result" do
      expect(described_class.progressive_variants("The Witcher 3: Wild Hunt (2015)")).to eq(
        [
          "The Witcher 3: Wild Hunt (2015)",
          "The Witcher 3: Wild Hunt",
          "The Witcher 3 Wild Hunt",
          "Witcher 3 Wild Hunt"
        ]
      )
    end

    it "dedupes steps that change nothing" do
      expect(described_class.progressive_variants("Hades")).to eq([ "Hades" ])
    end

    it "returns nothing for a blank title" do
      expect(described_class.progressive_variants("   ")).to eq([])
    end
  end

  describe ".exact_match?" do
    it "matches titles that are equal after normalisation, ignoring case" do
      expect(described_class.exact_match?("FINAL FANTASY® VII (1997)", "Final Fantasy VII")).to be(true)
    end

    it "ignores leading articles and colons" do
      expect(described_class.exact_match?("The Witcher 3: Wild Hunt", "Witcher 3 - Wild Hunt")).to be(true)
    end

    it "rejects different titles" do
      expect(described_class.exact_match?("Final Fantasy VII", "Final Fantasy VII Remake")).to be(false)
    end
  end
end

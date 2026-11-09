# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gamedb::TitleArticle do
  describe ".to_end" do
    it "moves a leading The, A or An to the end of the whole title" do
      expect(described_class.to_end("The Witcher 3: Wild Hunt")).to eq("Witcher 3: Wild Hunt, The")
      expect(described_class.to_end("A Hat in Time")).to eq("Hat in Time, A")
      expect(described_class.to_end("An Untitled Story")).to eq("Untitled Story, An")
    end

    it "keeps the article's casing and moves it for one-word titles too" do
      expect(described_class.to_end("THE ROOM")).to eq("ROOM, THE")
      expect(described_class.to_end("the Sims")).to eq("Sims, the")
    end

    it "is idempotent and leaves titles without a leading article alone" do
      expect(described_class.to_end("Sims, The")).to eq("Sims, The")
      expect(described_class.to_end("Theme Hospital")).to eq("Theme Hospital")
      expect(described_class.to_end("Legend of Zelda: A Link to the Past, The"))
        .to eq("Legend of Zelda: A Link to the Past, The")
    end

    it "leaves a title that is only an article, trimming whitespace" do
      expect(described_class.to_end("  The  ")).to eq("The")
    end
  end

  describe ".to_front" do
    it "moves a trailing article back to the front" do
      expect(described_class.to_front("Sims, The")).to eq("The Sims")
      expect(described_class.to_front("Witcher 3: Wild Hunt, The")).to eq("The Witcher 3: Wild Hunt")
    end

    it "leaves titles without a trailing article alone" do
      expect(described_class.to_front("Chrono Trigger")).to eq("Chrono Trigger")
      expect(described_class.to_front("Catherine")).to eq("Catherine")
    end
  end

  describe ".strip" do
    it "drops a leading or trailing article" do
      expect(described_class.strip("The Last of Us")).to eq("Last of Us")
      expect(described_class.strip("Last of Us, The")).to eq("Last of Us")
      expect(described_class.strip(" Last of Us ")).to eq("Last of Us")
    end
  end
end

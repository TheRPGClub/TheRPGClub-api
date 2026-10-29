# frozen_string_literal: true

require "rails_helper"

# Fixtures ported from the bot's matching behaviour:
# - #find follows buildImportCandidates (ImportCandidateUtils.ts): the first
#   progressive variant with hits wins, results are scored 100/85/70/word×60,
#   kept when score > 0 or in the top 3, and capped at 5.
# - #find_with_fallback follows Completionator's searchGameDbWithFallback:
#   progressive variants, then colon/"The" permutations, then a token union.
# Both run against GamedbGame.search on the real test database. Titles carry a
# random marker so rows left by other specs can never match.
RSpec.describe Imports::CandidateFinder do
  subject(:finder) { described_class.new }

  let(:tag) { "Zq#{SecureRandom.alphanumeric(6).downcase}" }

  def game!(title, **attrs)
    create(:game, title: title, **attrs)
  end

  describe "#find" do
    it "ranks exact, prefix, contains and word-overlap matches in that order" do
      contains = game!("Return to #{tag}", total_rating: 99)
      prefix = game!("#{tag} II", total_rating: 90)
      exact = game!(tag)

      result = finder.find(tag)

      expect(result.map(&:game_id)).to eq([ exact.game_id, prefix.game_id, contains.game_id ])
      expect(result.map(&:score)).to eq([ 100, 85, 70 ])
    end

    it "breaks score ties by title" do
      b = game!("#{tag} Beta")
      a = game!("#{tag} Alpha")

      expect(finder.find(tag).map(&:game_id)).to eq([ a.game_id, b.game_id ])
    end

    it "scores partial word overlap as matched words / search words x 60" do
      game!("Return of the Hero", slug: "#{tag}-hero-return-quest")

      result = finder.find("#{tag}-hero-return-quest")

      # "zq... hero return quest" vs "return of the hero": 2 of 4 words.
      expect(result.map(&:score)).to eq([ 30 ])
    end

    it "keeps the top 3 even when nothing scores above 0" do
      4.times { |i| game!("Unrelated #{i} #{SecureRandom.hex(3)}", slug: "#{tag}-slug-#{i}") }

      result = finder.find("#{tag}-slug")

      expect(result.size).to eq(3)
      expect(result.map(&:score)).to all(eq(0))
    end

    it "caps the candidates at 5" do
      7.times { |i| game!("#{tag} Quest #{i}") }

      expect(finder.find(tag).size).to eq(5)
    end

    it "stops at the first progressive variant with hits" do
      colon = game!("#{tag}: Remastered Edition")
      game!("#{tag} Remastered HD")

      result = finder.find("#{tag}: Remastered (1995)")

      expect(result.map(&:game_id)).to eq([ colon.game_id ])
    end

    it "falls through to later variants when earlier ones have no hits" do
      game = game!("#{tag} Wild Hunt")

      expect(finder.find("The #{tag}: Wild Hunt (2015)").map(&:game_id)).to eq([ game.game_id ])
    end

    it "returns nothing when no variant has hits" do
      expect(finder.find("#{tag} nothing here")).to eq([])
    end

    it "returns nothing for a blank title" do
      expect(finder.find("  ")).to eq([])
    end

    it "strips trademark, registered and copyright marks before NFKC, so \"Game™\" finds \"Game\"" do
      game = game!(tag)

      %W[#{tag}\u2122 #{tag}\u00AE \u00A9#{tag}].each do |title|
        result = finder.find(title)

        expect(result.map(&:game_id)).to eq([ game.game_id ])
        expect(result.first.score).to eq(100)
        expect(Imports::TitleNormalizer.exact_match?(title, result.first.title)).to be(true)
      end
    end
  end

  describe "#find_with_fallback" do
    it "returns every hit of the first progressive variant with hits" do
      games = 7.times.map { |i| game!("#{tag} Saga #{i}") }

      expect(finder.find_with_fallback("#{tag} Saga").map(&:game_id)).to match_array(games.map(&:game_id))
    end

    it "tries the colon permutations when the progressive variants miss" do
      game = game!("#{tag}: The Wild Hunt")

      expect(finder.find_with_fallback("#{tag}: Wild Hunt").map(&:game_id)).to eq([ game.game_id ])
    end

    it "unions token-by-token hits as a last resort" do
      first = game!("#{tag}alpha Majora")
      second = game!("Song of #{tag}omega")

      result = finder.find_with_fallback("#{tag}alpha #{tag}omega")

      expect(result.map(&:game_id)).to eq([ first.game_id, second.game_id ])
    end
  end

  describe ".confidence" do
    let(:candidates) { [ Imports::Candidate.new(game_id: 1, title: "Hades", score: 100) ] }

    it "is exact when the top candidate title equals the search title, ignoring case" do
      expect(described_class.confidence("hades", candidates)).to eq("exact")
    end

    it "is fuzzy otherwise" do
      expect(described_class.confidence("Hades II", candidates)).to eq("fuzzy")
    end

    it "is nil without candidates" do
      expect(described_class.confidence("Hades", [])).to be_nil
    end
  end

  describe ".dump / .load" do
    it "round-trips candidates through the bot's match_candidate_json shape" do
      candidates = [ Imports::Candidate.new(game_id: 7, title: "Hades", score: 100) ]

      json = described_class.dump(candidates)

      expect(JSON.parse(json)).to eq([ { "gameId" => 7, "title" => "Hades" } ])
      expect(described_class.load(json).map(&:to_h)).to eq([ { game_id: 7, title: "Hades", score: nil } ])
    end

    it "loads blank or malformed JSON as no candidates" do
      expect(described_class.load(nil)).to eq([])
      expect(described_class.load("not json")).to eq([])
    end
  end
end

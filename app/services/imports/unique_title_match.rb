# frozen_string_literal: true

module Imports
  # Links a free-text title to a GameDB game only when the match is certain:
  # exactly one GameDB candidate (Imports::CandidateFinder#find) is an exact
  # match after Imports::TitleNormalizer.exact_match? (case, punctuation and
  # similar noise ignored).
  #
  # It tries the title as given first, then the title without edition noise
  # ("Remastered", "GOTY Edition"...). The first variant with any exact match
  # decides: one game is a match, several are ambiguous. Used by
  # Achievements::LinkSetToGame and the giveaway key donation and backfill.
  class UniqueTitleMatch
    Result = Data.define(:status, :game_id) do
      def matched? = status == :matched
      def ambiguous? = status == :ambiguous
    end

    def self.call(title, finder: CandidateFinder.new)
      new(finder).call(title)
    end

    def initialize(finder = CandidateFinder.new)
      @finder = finder
    end

    # Result with status :matched (and the game_id), :ambiguous or :none.
    def call(title)
      title_variants(title).each do |variant|
        exact = @finder.find(variant)
          .select { |candidate| TitleNormalizer.exact_match?(variant, candidate.title) }
          .uniq(&:game_id)
        return Result.new(status: :matched, game_id: exact.first.game_id) if exact.one?
        return Result.new(status: :ambiguous, game_id: nil) if exact.many?
      end
      Result.new(status: :none, game_id: nil)
    end

    private

    def title_variants(title)
      title = title.to_s.strip
      [ title, TitleNormalizer.without_edition(title) ].compact_blank.uniq
    end
  end
end

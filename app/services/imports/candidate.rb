# frozen_string_literal: true

module Imports
  # One GameDB match for an import row. `score` is the CandidateFinder#find
  # ranking score (0..100); it is nil for unscored candidates (fallback search,
  # candidates loaded back from match_candidate_json).
  Candidate = Data.define(:game_id, :title, :score) do
    def initialize(game_id:, title:, score: nil)
      super
    end
  end
end

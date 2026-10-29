# frozen_string_literal: true

module Imports
  # The JSON shape of an import's GameDB candidates for the web workflow
  # endpoints (`ImportCandidate` in the OpenAPI schemas):
  #
  #   Imports::CandidatePresenter.as_json(candidates)
  #   # => [{ game_id: 1, title: "Hollow Knight", cover_url: "https://..." }]
  #
  # Covers are read in one query (images preloaded), in candidate order.
  module CandidatePresenter
    module_function

    def as_json(candidates)
      return [] if candidates.empty?

      games = GamedbGame.includes(:images).where(game_id: candidates.map(&:game_id)).index_by(&:game_id)
      candidates.map do |candidate|
        { game_id: candidate.game_id, title: candidate.title, cover_url: games[candidate.game_id]&.cover_url }
      end
    end
  end
end

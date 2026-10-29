# frozen_string_literal: true

# The `ImportCandidate` JSON shape shared by the import workflow review
# payloads (#289, #290): candidates in their ranked order, each with its
# game's primary cover, read in one query.
#
#   import_candidates_json([Imports::Candidate.new(game_id: 1, title: "Hades")])
#   # => [{ game_id: 1, title: "Hades", cover_url: "https://..." }]
module ImportCandidatesJson
  extend ActiveSupport::Concern

  private

  def import_candidates_json(candidates)
    return [] if candidates.empty?

    games = GamedbGame.where(game_id: candidates.map(&:game_id)).includes(:images).index_by(&:game_id)
    candidates.map do |candidate|
      { game_id: candidate.game_id, title: candidate.title, cover_url: games[candidate.game_id]&.cover_url }
    end
  end
end

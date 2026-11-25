# frozen_string_literal: true

# The anonymous vote tally GotmVote and NrGotmVote share: votes per
# Nomination, counts only, never who cast them. VotesController#*_tally
# serves it for one ballot; Gotm::RoundDetail groups it by ballot too.
module VoteCounts
  extend ActiveSupport::Concern

  included do
    # One row per Nomination (with its game) holding `vote_count`.
    # Nominations with no votes have no row.
    scope :vote_counts, -> {
      group(:nomination_id, :gamedb_game_id).select(:nomination_id, :gamedb_game_id, "COUNT(*) AS vote_count")
    }
  end
end

# frozen_string_literal: true

module Voting
  # A round's votes counted per game, on its main ballot or, with
  # `runoff: true`, its tie-breaker runoff. Vote rows denormalize their
  # nomination's game, and a member votes for a game at most once per ballot
  # however many nominations it has, so this is each game's real support.
  module Tally
    module_function

    def by_game(vote_model, round_number, runoff: false)
      vote_model.where(round_number: round_number, runoff: runoff).group(:gamedb_game_id).count
    end

    # Every game sharing the top count; empty when nobody voted.
    def leaders(vote_model, round_number, runoff: false)
      counts = by_game(vote_model, round_number, runoff: runoff)
      top = counts.values.max
      return [] if top.nil? || top.zero?

      counts.select { |_game_id, count| count == top }.keys.sort
    end
  end
end

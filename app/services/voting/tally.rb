# frozen_string_literal: true

module Voting
  # A round's votes counted per game. Vote rows denormalize their
  # nomination's game, and a member votes for a game at most once however many
  # nominations it has, so this is each game's real support.
  module Tally
    module_function

    def by_game(vote_model, round_number)
      vote_model.where(round_number: round_number).group(:gamedb_game_id).count
    end

    # Every game sharing the top count; empty when nobody voted.
    def leaders(vote_model, round_number)
      counts = by_game(vote_model, round_number)
      top = counts.values.max
      return [] if top.nil? || top.zero?

      counts.select { |_game_id, count| count == top }.keys.sort
    end
  end
end

# frozen_string_literal: true

module Voting
  # Votes counted per game. A vote row denormalizes its game and a member
  # votes for a game at most once per ballot, so this is each game's real
  # support. #count and #top work on any ballot's vote rows (a GOTM round's
  # category, a GOTY Vote's Award); #by_game and #leaders are the GOTM round
  # forms, on its main ballot or, with `runoff: true`, its runoff.
  module Tally
    module_function

    # { gamedb_game_id => votes } for a ballot's vote rows.
    def count(scope)
      scope.group(:gamedb_game_id).count
    end

    # Every game sharing the top count, sorted; empty when nobody voted.
    def top(counts)
      most = counts.values.max
      return [] if most.nil? || most.zero?

      counts.select { |_game_id, votes| votes == most }.keys.sort
    end

    def by_game(vote_model, round_number, runoff: false)
      count(vote_model.where(round_number: round_number, runoff: runoff))
    end

    def leaders(vote_model, round_number, runoff: false)
      top(by_game(vote_model, round_number, runoff: runoff))
    end
  end
end

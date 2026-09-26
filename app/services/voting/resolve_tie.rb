# frozen_string_literal: true

module Voting
  # An admin breaks a category's tie by picking one or more of the tied games
  # (a round may legitimately have two winners). Once no category is left
  # tied, the round is decided and the next one scheduled.
  class ResolveTie
    class NoTieError < StandardError; end
    class InvalidPickError < StandardError; end

    def initialize(round, category:, gamedb_game_ids:, now: Time.current)
      @round = round
      @category = category.to_s
      @picks = Array(gamedb_game_ids).map(&:to_i).uniq
      @now = now
    end

    def call
      @round.with_lock do
        tied = Array(@round.pending_ties[@category])
        raise NoTieError, "round #{@round.round_number} has no pending #{@category} tie" if tied.empty?
        if @picks.empty? || (@picks - tied).any?
          raise InvalidPickError, "pick one or more of the tied games: #{tied.join(', ')}"
        end

        Winners.record!(Voting.models_for(@category).fetch(:entry), @round, @picks)
        remaining = @round.pending_ties.except(@category)
        @round.update!(pending_ties: remaining)
        if remaining.empty?
          @round.decide!(@now)
          VotingEvent.emit!(
            round_number: @round.round_number, kind: "round_decided",
            payload: { winners: Winners.for_round(@round.round_number) }
          )
        end
        @round
      end
    end
  end
end

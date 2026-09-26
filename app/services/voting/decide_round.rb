# frozen_string_literal: true

module Voting
  # Finalizes a round once its voting window has closed: per category, a sole
  # leader in the tally is recorded as the winner, a shared lead becomes a
  # pending tie for an admin to break (Voting::ResolveTie), and a category
  # nobody voted in records nothing. With no ties the round is decided and the
  # next one scheduled, all in one transaction.
  class DecideRound
    class VotingNotClosedError < StandardError; end

    Result = Struct.new(:round, :winners, :ties, keyword_init: true)

    def initialize(round, now: Time.current)
      @round = round
      @now = now
    end

    def call
      @round.with_lock do
        raise VotingNotClosedError, "voting for round #{@round.round_number} has not closed" unless @round.voting_ended?(@now)
        return result if @round.closed_at.present?

        ties = {}
        Voting::CATEGORIES.each_key do |category|
          models = Voting.models_for(category)
          leaders = Tally.leaders(models.fetch(:vote), @round.round_number)
          next if leaders.empty?

          if leaders.one?
            Winners.record!(models.fetch(:entry), @round, leaders)
          else
            ties[category] = leaders
          end
        end

        @round.update!(closed_at: @now, pending_ties: ties)
        @round.decide!(@now) if ties.empty?
        result
      end
    end

    private

    def result
      Result.new(round: @round, winners: Winners.for_round(@round.round_number), ties: @round.pending_ties)
    end
  end
end

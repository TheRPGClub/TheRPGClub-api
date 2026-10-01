# frozen_string_literal: true

module Voting
  # Finalizes a round's tie-breaker runoff once its window has closed: per
  # category still awaiting a decision, a sole leader in the runoff tally is
  # recorded as the winner, and a runoff that ties again (or that nobody voted
  # in) is left in pending_ties for an admin to pick (Voting::ResolveTie). A
  # category an admin already settled during the runoff is not revisited.
  # With nothing left tied the round is decided and the next one scheduled.
  class DecideRunoff
    class RunoffNotClosedError < StandardError; end

    Result = Struct.new(:round, :winners, :ties, keyword_init: true)

    def initialize(round, now: Time.current)
      @round = round
      @now = now
    end

    def call
      @round.with_lock do
        unless @round.runoff_ended?(@now)
          raise RunoffNotClosedError, "the runoff for round #{@round.round_number} has not closed"
        end
        return result if @round.runoff_closed_at.present? || @round.decided_at.present?

        ties = {}
        @round.pending_ties.each do |category, tied|
          models = Voting.models_for(category)
          leaders = Tally.leaders(models.fetch(:vote), @round.round_number, runoff: true) & tied

          if leaders.one?
            Winners.record!(models.fetch(:entry), @round, leaders)
          else
            ties[category] = leaders.presence || tied
          end
        end

        @round.update!(runoff_closed_at: @now, pending_ties: ties)
        @round.decide!(@now) if ties.empty?
        result
      end
    end

    private

    # Only the categories the runoff was for; the rest were decided by the
    # main vote and announced with it.
    def result
      winners = Winners.for_round(@round.round_number).slice(*@round.runoff_ties.keys)
      Result.new(round: @round, winners: winners, ties: @round.pending_ties)
    end
  end
end

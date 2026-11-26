# frozen_string_literal: true

module Voting
  # Finalizes a round's tie-breaker runoff once its window has closed: per
  # category still awaiting a decision, a sole leader in the runoff tally is
  # recorded as the winner, and a runoff that ties again (or that nobody voted
  # in) is left in pending_ties for an admin to pick (Voting::ResolveTie). A
  # category an admin already settled during the runoff is not revisited.
  # With nothing left tied the round is decided, the next one scheduled and
  # the website's Share Card refresh queued once it commits (ShareCard).
  # The steps are Voting::Decide's, shared with the GOTY Vote.
  class DecideRunoff
    RunoffNotClosedError = Decide::RunoffNotClosedError

    Result = Struct.new(:round, :winners, :ties, keyword_init: true)

    def initialize(round, now: Time.current)
      @round = round
      @now = now
    end

    # The result names only the categories the runoff was for; the rest were
    # decided by the main vote and announced with it.
    def call
      Decide.close_runoff!(RoundContest.new(@round), now: @now) do |round|
        ShareCard.refresh_later if round.decided_at.present?
      end
      winners = Winners.for_round(@round.round_number).slice(*@round.runoff_ties.keys)
      Result.new(round: @round, winners: winners, ties: @round.pending_ties)
    end
  end
end

# frozen_string_literal: true

module Voting
  # Finalizes a round once its voting window has closed: per category, a sole
  # leader in the tally is recorded as the winner, a shared lead goes to a
  # runoff limited to the tied games (Voting::DecideRunoff settles it), and a
  # category nobody voted in records nothing. With no ties the round is
  # decided and the next one scheduled, all in one transaction, and the
  # website's Share Card refresh queued once it commits (ShareCard). The steps
  # are Voting::Decide's, shared with the GOTY Vote.
  class DecideRound
    VotingNotClosedError = Decide::VotingNotClosedError

    Result = Struct.new(:round, :winners, :ties, keyword_init: true)

    def initialize(round, now: Time.current)
      @round = round
      @now = now
    end

    def call
      Decide.close!(RoundContest.new(@round), now: @now) do |round|
        ShareCard.refresh_later if round.decided_at.present?
      end
      Result.new(round: @round, winners: Winners.for_round(@round.round_number), ties: @round.pending_ties)
    end
  end
end

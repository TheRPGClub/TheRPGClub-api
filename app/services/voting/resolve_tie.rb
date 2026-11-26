# frozen_string_literal: true

module Voting
  # An admin breaks a category's tie by picking one or more of the tied games
  # (a round may legitimately have two winners): the last resort once a
  # runoff has tied again, or a shortcut that settles a category while its
  # runoff is still open. Once no category is left tied, the round is decided,
  # the next one scheduled, the round_decided post queued and the website's
  # Share Card refresh queued once it commits (ShareCard). The steps are
  # Voting::Decide's, shared with the GOTY Vote.
  class ResolveTie
    NoTieError = Decide::NoTieError
    InvalidPickError = Decide::InvalidPickError

    def initialize(round, category:, gamedb_game_ids:, now: Time.current)
      @round = round
      @category = category.to_s
      @picks = Array(gamedb_game_ids).map(&:to_i).uniq
      @now = now
    end

    def call
      Decide.resolve_tie!(RoundContest.new(@round), @category, @picks, now: @now) do
        ShareCard.refresh_later
        VotingEvent.emit!(
          round_number: @round.round_number, kind: "round_decided",
          payload: { winners: Winners.for_round(@round.round_number) }
        )
      end
      @round
    end
  end
end

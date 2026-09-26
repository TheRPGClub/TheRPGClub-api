# frozen_string_literal: true

module Voting
  # Creates the round the club is currently nominating for or voting on from
  # the bot's bookkeeping, for the first deploy of voting_rounds: the round
  # after the last one with recorded GOTM winners. Its vote opens at its own
  # bot_voting_info row when /admin voting-open already created one, otherwise
  # at the decided round's re-dated next_vote_at (see Voting::LegacySync).
  module Backfill
    module_function

    def call
      return if VotingRound.exists?

      last_decided = GotmEntry.maximum(:round_number)
      return if last_decided.nil?

      target = last_decided + 1
      own = BotVotingInfo.find_by(round_number: target)
      opens = own&.next_vote_at || BotVotingInfo.find_by(round_number: last_decided)&.next_vote_at
      return if opens.nil?

      VotingRound.create!(round_number: target, voting_opens_at: opens, voting_closes_at: own&.vote_ends_at)
    end
  end
end

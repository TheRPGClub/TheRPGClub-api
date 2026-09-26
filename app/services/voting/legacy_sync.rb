# frozen_string_literal: true

module Voting
  # Keeps voting_rounds in step with the bot while it still drives the round
  # lifecycle through bot_voting_info and its round-setup wizard (automation
  # off). This is the one place the old row semantics are decoded:
  #
  # - bot_voting_info row R's next_vote_at means round R's own vote while R is
  #   undecided (the bot's /admin voting-open creates that row), and round
  #   R + 1's vote once R has winners (the wizard re-dates the row).
  # - the wizard POSTing a round's gotm_entries is what decides it.
  #
  # Delete together with the voting_info endpoints once the bot reads
  # voting_rounds and voting_events instead.
  module LegacySync
    module_function

    def voting_info_written(info)
      return if Voting.automation_enabled?

      if GotmEntry.exists?(round_number: info.round_number)
        schedule!(info.round_number + 1, opens: info.next_vote_at)
      else
        schedule!(info.round_number, opens: info.next_vote_at, closes: info.vote_ends_at)
      end
    end

    def winner_recorded(round_number)
      return if Voting.automation_enabled?

      round = VotingRound.find_by(round_number: round_number)
      return if round.nil? || round.decided_at.present?

      round.with_lock { round.decide! }
    end

    # Decided rounds are history; the bot re-dating their rows is about the
    # next round, handled above.
    def schedule!(round_number, opens:, closes: nil)
      round = VotingRound.find_or_initialize_by(round_number: round_number)
      return if round.decided_at.present?

      round.voting_opens_at = opens
      round.voting_closes_at = closes if closes.present?
      round.save!
    end
  end
end

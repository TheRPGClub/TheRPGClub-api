# frozen_string_literal: true

# The bot's legacy round bookkeeping, still written by its /admin commands and
# round-setup wizard. The round lifecycle itself lives in VotingRound;
# Voting::LegacySync mirrors every write here into it.
class BotVotingInfo < ApplicationRecord
  self.table_name = "bot_voting_info"
  self.primary_key = "round_number"

  # When voting closes (#172): the explicit vote_ends_at override, else the
  # default weekend window after next_vote_at (Voting::Schedule).
  def vote_deadline
    return vote_ends_at if vote_ends_at.present?
    return nil if next_vote_at.blank?

    Voting::Schedule.default_closes_at(next_vote_at)
  end

  def voting_open?(now = Time.current)
    next_vote_at.present? && now >= next_vote_at && now < vote_deadline
  end

  def voting_ended?(now = Time.current)
    vote_deadline.present? && now >= vote_deadline
  end
end

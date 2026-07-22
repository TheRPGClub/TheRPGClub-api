# frozen_string_literal: true

class BotVotingInfo < ApplicationRecord
  self.table_name = "bot_voting_info"
  self.primary_key = "round_number"

  # The bot computes its reminder schedule in US Eastern; the default voting
  # deadline follows the same convention so "Sunday" means the club's Sunday.
  VOTING_TIME_ZONE = "America/New_York"

  # When voting closes (#172). The voting period runs Friday -> Sunday: it opens at
  # next_vote_at (the vote is scheduled on a Friday) and by default ends at the
  # end of the first Sunday at/after it. An explicit vote_ends_at overrides the
  # default, e.g. to extend a round's voting window.
  def vote_deadline
    return vote_ends_at if vote_ends_at.present?
    return nil if next_vote_at.blank?

    opens = next_vote_at.in_time_zone(VOTING_TIME_ZONE)
    days_until_sunday = (7 - opens.wday) % 7 # wday: Sunday == 0
    (opens + days_until_sunday.days).end_of_day
  end

  def voting_open?(now = Time.current)
    next_vote_at.present? && now >= next_vote_at && now < vote_deadline
  end

  # Whether member nominations are open for the given round. Nominations
  # collect for the round AFTER the current (highest) one — the bot's
  # /nominate convention — and close when the current round's vote opens
  # (next_vote_at). Only that single round is ever open: earlier rounds are
  # frozen history and later ones aren't accepting yet.
  def self.nominations_open_for?(round_number, now = Time.current)
    current = order(round_number: :desc).first
    return false if current.nil? || current.next_vote_at.blank?

    round_number.to_i == current.round_number + 1 && now < current.next_vote_at
  end

  # Once voting has ended, vote rows stop being anonymous: voter identities
  # become readable by any authenticated caller (see VotesController).
  def voting_ended?(now = Time.current)
    vote_deadline.present? && now >= vote_deadline
  end
end

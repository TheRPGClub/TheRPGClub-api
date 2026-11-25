# frozen_string_literal: true

# The voting windows a GOTM round (VotingRound) and a GOTY Vote (GotyVote)
# share: a main vote from `voting_opens_at` until `voting_closes_at`, then,
# for whatever the tally left tied, one runoff from `runoff_opens_at` until
# `runoff_closes_at`, and whatever that leaves tied waits in `pending_ties`
# for an admin. `pending_ties` and `runoff_ties` map a key (a category or an
# Award) to its tied game ids.
#
# The phase is derived from the timestamps at read time; a record names what
# comes before voting in #phase_before_voting. Between a window closing and
# its tally the phase reads `closed`. The Voting::Decide steps drive the side
# effects through #open_runoff! and #decide!.
module VoteWindows
  extend ActiveSupport::Concern

  def phase(now = Time.current)
    return "decided" if decided_at.present?

    before = phase_before_voting(now)
    return before if before
    return "voting" if now < voting_closes_at
    if runoff_closes_at.present?
      return "runoff" if now < runoff_closes_at
      # The window has run out but the runoff's tally is not in yet.
      return "closed" if runoff_closed_at.nil?
    end
    return "tie" if pending_ties.present?

    "closed"
  end

  def voting_open?(now = Time.current)
    phase(now) == "voting"
  end

  def voting_ended?(now = Time.current)
    %w[closed runoff tie decided].include?(phase(now))
  end

  def runoff_open?(now = Time.current)
    phase(now) == "runoff"
  end

  # Whether there was a runoff and it is over (its window ran out, or an
  # admin settled every tied key first).
  def runoff_ended?(now = Time.current)
    runoff_closes_at.present? && voting_ended?(now) && !runoff_open?(now)
  end

  # Puts the tied keys to a runoff opening now. The caller holds the row lock.
  def open_runoff!(ties, now = Time.current)
    update!(closed_at: now, pending_ties: ties, runoff_ties: ties,
      runoff_opens_at: now, runoff_closes_at: now + Voting.runoff_duration)
  end

  # Records the vote as decided. Idempotent; the caller holds the row lock
  # and has already recorded the winners.
  def decide!(now = Time.current)
    return if decided_at.present?

    update!(closed_at: closed_at || now, decided_at: now, pending_ties: {})
  end
end

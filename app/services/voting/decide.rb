# frozen_string_literal: true

module Voting
  # The decision steps a GOTM round and a GOTY Vote share, run over a
  # *contest*: an adapter naming the record (a VoteWindows record) and how to
  # count and record its keys (a round's categories, a GOTY Vote's Awards).
  # Voting::RoundContest and Goty::Contest are the two. A contest answers:
  #
  # - `record`, and `label` for messages ("round 12", "GOTY Vote 2026");
  # - `keys`: what the main vote decides;
  # - `uncontested(key)`: the game a key goes to without a vote (a lone
  #   candidate), or nil;
  # - `leaders(key, runoff:)`: the games sharing the top count (Tally.top);
  # - `record_winners!(key, game_ids, decided_by:)`, decided_by one of
  #   DECIDED_BY.
  #
  # Each step holds the record's row lock, is idempotent, and returns whether
  # it acted. A block given to a step runs inside that lock, only when the
  # step acted (for #resolve_tie!, only when it decided the record), so a
  # caller can queue its posts exactly once in the same transaction.
  module Decide
    class VotingNotClosedError < StandardError; end
    class RunoffNotClosedError < StandardError; end
    class NoTieError < StandardError; end
    class InvalidPickError < StandardError; end

    DECIDED_BY = %w[vote runoff admin uncontested].freeze

    module_function

    # Once the main vote has closed: per key, a lone candidate wins as
    # `uncontested`, a sole leader in the tally wins by `vote`, a shared lead
    # goes to one runoff for every tied key, and a key nobody voted in
    # records nothing. With no ties the record is decided.
    def close!(contest, now: Time.current)
      record = contest.record
      record.with_lock do
        raise VotingNotClosedError, "voting for #{contest.label} has not closed" unless record.voting_ended?(now)
        next false if record.closed_at.present?

        ties = {}
        contest.keys.each do |key|
          if (sole = contest.uncontested(key))
            contest.record_winners!(key, [ sole ], decided_by: "uncontested")
            next
          end

          leaders = contest.leaders(key, runoff: false)
          next if leaders.empty?

          if leaders.one?
            contest.record_winners!(key, leaders, decided_by: "vote")
          else
            ties[key] = leaders
          end
        end

        ties.empty? ? record.decide!(now) : record.open_runoff!(ties, now)
        yield record if block_given?
        true
      end
    end

    # Once the runoff has closed: per key still tied, a sole leader among its
    # tied games wins by `runoff`; a runoff that ties again (or that nobody
    # voted in) stays pending for an admin, narrowed to its leaders. A key an
    # admin settled during the runoff is not revisited. With nothing left
    # tied the record is decided.
    def close_runoff!(contest, now: Time.current)
      record = contest.record
      record.with_lock do
        raise RunoffNotClosedError, "the runoff for #{contest.label} has not closed" unless record.runoff_ended?(now)
        next false if record.runoff_closed_at.present? || record.decided_at.present?

        ties = {}
        record.pending_ties.each do |key, tied|
          leaders = contest.leaders(key, runoff: true) & tied
          if leaders.one?
            contest.record_winners!(key, leaders, decided_by: "runoff")
          else
            ties[key] = leaders.presence || tied
          end
        end

        record.update!(runoff_closed_at: now, pending_ties: ties)
        record.decide!(now) if ties.empty?
        yield record if block_given?
        true
      end
    end

    # An admin settles a key's tie by picking among its tied games: the last
    # resort once a runoff tied again, or a shortcut while the runoff is
    # open. Once no key is left tied the record is decided. Returns whether
    # this call decided it.
    def resolve_tie!(contest, key, picks, now: Time.current)
      record = contest.record
      key = key.to_s
      record.with_lock do
        tied = Array(record.pending_ties[key])
        raise NoTieError, "#{contest.label} has no pending #{key} tie" if tied.empty?
        if picks.empty? || (picks - tied).any?
          raise InvalidPickError, "pick one or more of the tied games: #{tied.join(', ')}"
        end

        contest.record_winners!(key, picks, decided_by: "admin")
        remaining = record.pending_ties.except(key)
        record.update!(pending_ties: remaining)
        next false unless remaining.empty?

        record.decide!(now)
        yield record if block_given?
        true
      end
    end
  end
end

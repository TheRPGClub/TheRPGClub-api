# frozen_string_literal: true

module Voting
  # The casting rules a GOTM round's categories (Voting::CastVote) and a GOTY
  # Vote's Awards (Goty::CastVote) share. Each caller finds its ballot and the
  # member's votes on it; these rules decide what a cast does:
  #
  # - Which ballot is open (#open_ballot!): the main vote while the record is
  #   `voting`, the runoff while it is `runoff` and the key (category or
  #   Award) is still tied, limited to its tied games. Anything else raises
  #   VotingClosedError.
  # - The cap (#cap): half the ballot's games, rounded down, at least 1,
  #   evaluated at cast time; RUNOFF_CAP on the runoff ballot.
  # - Votes are per game: casting for a game the member already voted for
  #   toggles that vote off (#apply!).
  # - Casting a new game at the cap evicts the oldest vote(s), and the Result
  #   says what was removed so callers can warn the voter.
  # - Casts by one member on one ballot are serialized with a transaction
  #   scoped advisory lock (#lock!): row locks cannot stop two concurrent
  #   INSERTs from overshooting the cap. The tables' unique indexes remain the
  #   backstop.
  module CastRules
    class VotingClosedError < StandardError; end
    class GameNotInRunoffError < StandardError; end

    RUNOFF_CAP = 1

    Result = Struct.new(:action, :vote, :removed_votes, :cap, :runoff, :warning, keyword_init: true)

    module_function

    # The per-member cap for a ballot of `game_count` distinct games.
    def cap(game_count)
      [ game_count / 2, 1 ].max
    end

    # Raises unless `record` (a VoteWindows record) takes votes for `key`
    # now. Returns nil for the main vote, or the tied games a runoff cast must
    # pick from. `label` names the record in messages ("round 12", "GOTY Vote
    # 2026").
    def open_ballot!(record, key, label:, now: Time.current)
      case record.phase(now)
      when "voting" then nil
      when "runoff"
        tied = Array(record.pending_ties[key.to_s])
        raise VotingClosedError, "#{label} has no #{key} runoff" if tied.empty?

        tied
      when "upcoming", "nominating"
        raise VotingClosedError,
          "voting for #{label} has not opened yet (opens at #{record.voting_opens_at.iso8601})"
      else
        raise VotingClosedError, closed_message(record, label, now)
      end
    end

    # Held until commit or rollback; only blocks another cast by the same
    # member on the same ballot (modulo harmless hash collisions).
    def lock!(vote_model, user_id, ballot_key)
      sql = vote_model.sanitize_sql([
        "SELECT pg_advisory_xact_lock(hashtext(?), hashtext(?))",
        "#{vote_model.table_name}:#{user_id}",
        ballot_key.to_s
      ])
      vote_model.connection.execute(sql)
    end

    # Applies a cast for `gamedb_game_id` to the member's `votes` on the
    # ballot (oldest first): toggles an existing vote on the game off, or
    # evicts until there is room and creates the new vote with the block.
    # Call inside the transaction holding #lock!.
    def apply!(votes, gamedb_game_id:, cap:, runoff:)
      existing = votes.find { |vote| vote.gamedb_game_id == gamedb_game_id }
      return unvote!(existing, cap, runoff) if existing

      evicted = evict_until_room!(votes.dup, cap)
      vote = yield
      # Reload so the DB-defaulted voted_at is present on the returned row.
      Result.new(action: "voted", vote: vote.reload, removed_votes: evicted, cap: cap, runoff: runoff,
        warning: eviction_warning(evicted, cap, runoff))
    end

    def closed_message(record, label, now)
      if record.runoff_closes_at.present? && record.runoff_closes_at <= now
        "the runoff for #{label} closed at #{record.runoff_closes_at.iso8601}"
      else
        "voting for #{label} closed at #{record.voting_closes_at.iso8601}"
      end
    end

    def unvote!(vote, cap, runoff)
      vote.destroy!
      Result.new(action: "unvoted", vote: nil, removed_votes: [ vote ], cap: cap, runoff: runoff,
        warning: "Removed your vote for #{game_label(vote)}: voting again on a game you already voted for " \
                 "takes the vote back.")
    end

    # Normally evicts at most one, but recovers a member left over the cap
    # when the ballot shrank mid-window.
    def evict_until_room!(votes, cap)
      evicted = []
      while votes.size + 1 > cap
        oldest = votes.shift
        oldest.destroy!
        evicted << oldest
      end
      evicted
    end

    def eviction_warning(evicted, cap, runoff)
      return nil if evicted.empty?

      titles = evicted.map { |vote| game_label(vote) }.join(", ")
      if runoff
        "The runoff takes one vote, so your vote for #{titles} was removed to make room."
      elsif evicted.many?
        "You were at the vote cap (#{cap}), so your oldest votes (#{titles}) were removed to make room."
      else
        "You were at the vote cap (#{cap}), so your oldest vote (#{titles}) was removed to make room."
      end
    end

    def game_label(vote)
      vote.game&.title || "game ##{vote.gamedb_game_id}"
    end
  end
end

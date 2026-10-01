# frozen_string_literal: true

module Voting
  # Casts (or toggles off) a user's vote on a GOTM / NR-GOTM nomination (#172),
  # enforcing the round's voting window and the per-user vote cap. The same
  # class serves both categories — the controller names the category.
  #
  # Rules:
  # - Voting is open while the round's VotingRound is in its voting phase
  #   (voting_opens_at until voting_closes_at, never once decided); a cast
  #   outside it raises VotingClosedError.
  # - During the round's runoff phase a cast goes to the runoff ballot
  #   instead, only in a category still awaiting its runoff and only for one
  #   of that category's tied games (else GameNotInRunoffError). Runoff votes
  #   are separate rows (`runoff: true`), so the main vote stays intact.
  # - A user holds at most `cap` votes per round per category: half the
  #   category's distinct nominated games, rounded down, and at least 1 —
  #   evaluated at cast time. In a runoff the cap is RUNOFF_CAP.
  # - Votes are per game (vote rows denormalize the nomination's game):
  #   casting for a game the user already voted toggles that vote OFF, even
  #   when the earlier vote sits on a different nomination of the same game.
  # - Casting a new game while at the cap evicts the user's oldest vote(s);
  #   the Result reports what was removed so callers can warn the voter.
  #
  # Concurrency: casts for one (category, user, round) are serialized with a
  # transaction-scoped advisory lock — row locks alone cannot serialize the
  # concurrent INSERTs that would let a user overshoot the cap. The tables'
  # unique (round, ballot, user, game) index remains the backstop.
  class CastVote
    class VotingClosedError < StandardError; end
    class NominationNotFoundError < StandardError; end
    class NominationMissingGameError < StandardError; end
    class GameNotInRunoffError < StandardError; end

    RUNOFF_CAP = 1

    Result = Struct.new(:action, :vote, :removed_votes, :cap, :runoff, :warning, keyword_init: true)

    # The per-user vote cap for a round, from the size of its nomination
    # field. Votes are per game, so a game nominated twice counts once and a
    # nomination without a game (nothing to vote on) not at all. Class-level
    # so VotesController can surface the cap alongside the tally without
    # casting.
    def self.cap_for(nomination_model, round_number)
      games = nomination_model.where(round_number: round_number).where.not(gamedb_game_id: nil)
        .distinct.count(:gamedb_game_id)
      [ games / 2, 1 ].max
    end

    def initialize(category:)
      @category = category.to_s
      models = Voting.models_for(@category)
      @vote_model = models.fetch(:vote)
      @nomination_model = models.fetch(:nomination)
    end

    def cast!(round_number:, user_id:, nomination_id:)
      runoff_games = open_ballot!(round_number)
      runoff = !runoff_games.nil?

      @vote_model.transaction do
        acquire_cast_lock!(round_number, user_id)

        nomination = find_nomination!(round_number, nomination_id)
        if runoff && !runoff_games.include?(nomination.gamedb_game_id)
          raise GameNotInRunoffError, "nomination #{nomination_id} is not one of the games in the runoff"
        end

        votes = @vote_model
          .where(round_number: round_number, user_id: user_id, runoff: runoff)
          .order(voted_at: :asc, vote_id: :asc)
          .to_a
        cap = runoff ? RUNOFF_CAP : cap_for(round_number)

        existing = votes.find { |vote| vote.gamedb_game_id == nomination.gamedb_game_id }
        if existing
          unvote!(existing, cap, runoff)
        else
          vote!(votes, cap, runoff, round_number, user_id, nomination)
        end
      end
    end

    private

    # Raises unless the round takes votes in this category now. Returns nil
    # for the main vote, or the tied games a runoff cast must pick from.
    def open_ballot!(round_number)
      round = VotingRound.find_by(round_number: round_number)
      raise VotingClosedError, "voting is not scheduled for round #{round_number}" if round.nil?

      now = Time.current
      case round.phase(now)
      when "voting" then nil
      when "runoff"
        tied = Array(round.pending_ties[@category])
        raise VotingClosedError, "round #{round_number} has no #{@category} runoff" if tied.empty?

        tied
      when "nominating"
        raise VotingClosedError,
          "voting for round #{round_number} has not opened yet (opens at #{round.voting_opens_at.iso8601})"
      else
        raise VotingClosedError, closed_message(round, now)
      end
    end

    def closed_message(round, now)
      if round.runoff_closes_at.present? && round.runoff_closes_at <= now
        "the runoff for round #{round.round_number} closed at #{round.runoff_closes_at.iso8601}"
      else
        "voting for round #{round.round_number} closed at #{round.voting_closes_at.iso8601}"
      end
    end

    # pg_advisory_xact_lock holds until commit/rollback and only ever blocks
    # another cast by the same user in the same round and category (modulo
    # harmless hash collisions), so contention is effectively zero.
    def acquire_cast_lock!(round_number, user_id)
      sql = @vote_model.sanitize_sql([
        "SELECT pg_advisory_xact_lock(hashtext(?), hashtext(?))",
        "#{@vote_model.table_name}:#{user_id}",
        round_number.to_s
      ])
      @vote_model.connection.execute(sql)
    end

    def find_nomination!(round_number, nomination_id)
      nomination = @nomination_model.find_by(nomination_id: nomination_id, round_number: round_number)
      if nomination.nil?
        raise NominationNotFoundError, "nomination #{nomination_id} was not found in round #{round_number}"
      end
      # The GOTM nominations table allows a NULL game; such a row has nothing
      # to vote on under the one-vote-per-game rule.
      if nomination.gamedb_game_id.blank?
        raise NominationMissingGameError, "nomination #{nomination_id} has no game attached"
      end

      nomination
    end

    def cap_for(round_number)
      self.class.cap_for(@nomination_model, round_number)
    end

    def unvote!(vote, cap, runoff)
      vote.destroy!
      Result.new(
        action: "unvoted",
        vote: nil,
        removed_votes: [ vote ],
        cap: cap,
        runoff: runoff,
        warning: "Removed your vote for #{game_label(vote)} — voting again on a game you already voted for takes the vote back."
      )
    end

    def vote!(votes, cap, runoff, round_number, user_id, nomination)
      evicted = evict_until_room!(votes, cap)
      vote = @vote_model.create!(
        round_number: round_number,
        user_id: user_id,
        nomination_id: nomination.nomination_id,
        gamedb_game_id: nomination.gamedb_game_id,
        runoff: runoff
      )

      # Reload so the DB-defaulted voted_at is present on the returned row.
      Result.new(
        action: "voted",
        vote: vote.reload,
        removed_votes: evicted,
        cap: cap,
        runoff: runoff,
        warning: eviction_warning(evicted, cap, runoff)
      )
    end

    # Destroys the user's oldest votes until the new one fits under the cap.
    # Normally evicts at most one, but recovers a user left over the cap when
    # an admin deleted nominations mid-window and shrank the cap.
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

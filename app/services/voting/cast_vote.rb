# frozen_string_literal: true

module Voting
  # Casts (or toggles off) a user's vote on a GOTM / NR-GOTM nomination (#172),
  # enforcing the round's voting window and the per-user vote cap. The same
  # class serves both categories; the controller names the category. The
  # rules themselves are Voting::CastRules, shared with the GOTY Vote's
  # Awards.
  #
  # Round specifics:
  # - The ballot is the round's nominations: the cap is half the category's
  #   distinct nominated games (a game nominated twice counts once, a
  #   nomination without a game not at all).
  # - A vote is cast on a nomination; the row denormalizes its game, so
  #   casting for a game the user already voted for toggles that vote OFF,
  #   even when the earlier vote sits on a different nomination of the game.
  # - During the round's runoff a cast goes to the runoff ballot (separate
  #   `runoff: true` rows), only for one of the category's tied games.
  class CastVote
    VotingClosedError = CastRules::VotingClosedError
    GameNotInRunoffError = CastRules::GameNotInRunoffError
    class NominationNotFoundError < StandardError; end
    class NominationMissingGameError < StandardError; end

    RUNOFF_CAP = CastRules::RUNOFF_CAP

    Result = CastRules::Result

    # The per-user vote cap for a round, from the size of its nomination
    # field. Class-level so VotesController can surface the cap alongside the
    # tally without casting.
    def self.cap_for(nomination_model, round_number)
      games = nomination_model.where(round_number: round_number).where.not(gamedb_game_id: nil)
        .distinct.count(:gamedb_game_id)
      CastRules.cap(games)
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
        CastRules.lock!(@vote_model, user_id, round_number)

        nomination = find_nomination!(round_number, nomination_id)
        if runoff && !runoff_games.include?(nomination.gamedb_game_id)
          raise GameNotInRunoffError, "nomination #{nomination_id} is not one of the games in the runoff"
        end

        votes = @vote_model
          .where(round_number: round_number, user_id: user_id, runoff: runoff)
          .order(voted_at: :asc, vote_id: :asc)
          .to_a
        cap = runoff ? RUNOFF_CAP : self.class.cap_for(@nomination_model, round_number)

        CastRules.apply!(votes, gamedb_game_id: nomination.gamedb_game_id, cap: cap, runoff: runoff) do
          @vote_model.create!(round_number: round_number, user_id: user_id,
            nomination_id: nomination.nomination_id, gamedb_game_id: nomination.gamedb_game_id, runoff: runoff)
        end
      end
    end

    private

    def open_ballot!(round_number)
      round = VotingRound.find_by(round_number: round_number)
      raise VotingClosedError, "voting is not scheduled for round #{round_number}" if round.nil?

      CastRules.open_ballot!(round, @category, label: "round #{round_number}")
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
  end
end

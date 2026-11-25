# frozen_string_literal: true

module Api
  module V1
    # Votes on a GOTY Vote's Awards (spec api#471, ticket api#474). The rules
    # (window, cap, toggle, eviction, runoff) live in Goty::CastVote, on the
    # GOTM round's shared Voting::CastRules; this controller owns who may
    # cast for whom. Members see their votes and the tally on
    # GET /goty_votes/:year.
    class GotyBallotVotesController < ApplicationController
      include ActsForMember

      feature :goty_vote

      # POST /api/v1/goty_votes/:goty_vote_year/votes { data: { award, gamedb_game_id, user_id? } }
      # 201 when a vote was placed, 200 when the cast toggled one off. As for
      # GOTM votes, the response carries the cap, any removed votes and a
      # warning to show the voter.
      def create
        data = params.require(:data)
        award = data.require(:award)
        game_id = data.require(:gamedb_game_id)
        user_id = acting_member_id(data[:user_id]) or return

        result = Goty::CastVote.call(year: params[:goty_vote_year], award: award, user_id: user_id,
          gamedb_game_id: game_id)
        render json: { data: {
          action: result.action,
          vote: result.vote && GotyBallotVoteResource.new(result.vote).serializable_hash,
          removed_votes: result.removed_votes.map { |vote| GotyBallotVoteResource.new(vote).serializable_hash },
          cap: result.cap,
          runoff: result.runoff,
          warning: result.warning
        } }, status: result.action == "voted" ? :created : :ok
      rescue Goty::CastVote::UnknownAwardError => error
        render_error("unknown_award", error.message)
      rescue Voting::CastRules::VotingClosedError => error
        render_error("voting_closed", error.message)
      rescue Goty::CastVote::NotACandidateError => error
        render_error("not_a_candidate", error.message)
      rescue Goty::CastVote::UncontestedError => error
        render_error("uncontested", error.message)
      rescue Voting::CastRules::GameNotInRunoffError => error
        render_error("not_in_runoff", error.message)
      rescue ArgumentError, TypeError
        render_error("not_a_candidate", "gamedb_game_id must be a game id")
      end

      private

      def render_error(code, message)
        render json: { error: code, message: message }, status: :unprocessable_content
      end
    end
  end
end

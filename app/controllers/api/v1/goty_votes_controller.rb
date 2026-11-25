# frozen_string_literal: true

module Api
  module V1
    # The yearly GOTY Vote (spec api#471). Reads are open to any caller who
    # can use the Feature; nothing creates a GOTY Vote by hand (the lifecycle
    # sweep does, with the default schedule).
    class GotyVotesController < ApplicationController
      feature :goty_vote

      def index
        render_collection(GotyVote.all, resource: GotyVoteSummaryResource, default_order: { year: :desc })
      end

      def show
        vote = GotyVote.find(params[:year])
        render json: { data: GotyVoteResource.new(vote).serializable_hash }
      end

      # GET /api/v1/games/:id/goty_eligibility?year=: whether the game may be
      # nominated for that year's Game of the Year, and why not.
      def eligibility
        year = year_param or return
        game = GamedbGame.find(params[:id])
        result = Goty::Eligibility.check(game, year)
        render json: { data: {
          game_id: result.game_id, year: result.year, eligible: result.eligible?, reason: result.reason,
          released_on: result.released_on&.iso8601, date_precision: result.date_precision, source: result.source
        } }
      end

      private

      # The required ?year=, or nil after rendering 400.
      def year_param
        Integer(params.require(:year), 10)
      rescue ArgumentError
        render json: { error: "year must be a year, e.g. 2026" }, status: :bad_request
        nil
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    # The GOTM / NR-GOTM round lifecycle, owned here (see VotingRound). Reads
    # are open to any authenticated caller; rescheduling and tie-breaking are
    # admin/service. Nothing creates rounds by hand: deciding a round schedules
    # the next one.
    class VotingRoundsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[update resolve_tie]

      # Rescheduling fields. Moving the open without a close keeps the default
      # weekend window; "close voting now" is `voting_closes_at: <now>`.
      UPDATE_ATTRS = %w[voting_opens_at voting_closes_at month_year].freeze

      def index
        render_collection(VotingRound.all, resource: VotingRoundResource, default_order: { round_number: :desc })
      end

      # GET /api/v1/voting_rounds/current — the one round being nominated for,
      # voted on or awaiting its decision.
      def current
        round = VotingRound.current or raise ActiveRecord::RecordNotFound, "no voting round is scheduled"
        render_round(round)
      end

      def show
        render_round(VotingRound.find(params[:id]))
      end

      def update
        round = VotingRound.find(params[:id])
        if round.decided_at.present?
          return render json: { error: "round_decided", message: "round #{round.round_number} is already decided" },
            status: :unprocessable_entity
        end

        round.update!(request_data.slice(*UPDATE_ATTRS))
        render_round(round)
      end

      # POST /api/v1/voting_rounds/:id/resolve_tie { data: { category, gamedb_game_ids } }
      def resolve_tie
        data = request_data
        round = Voting::ResolveTie.new(
          VotingRound.find(params[:id]),
          category: data["category"],
          gamedb_game_ids: data["gamedb_game_ids"]
        ).call
        render_round(round)
      rescue Voting::ResolveTie::NoTieError => error
        render json: { error: "no_tie", message: error.message }, status: :unprocessable_entity
      rescue Voting::ResolveTie::InvalidPickError => error
        render json: { error: "invalid_pick", message: error.message }, status: :unprocessable_entity
      end

      private

      def render_round(round)
        render json: { data: VotingRoundResource.new(round).serializable_hash }
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    class DashboardsController < ApplicationController
      # The latest GOTM and NR-GOTM winners belong to Voting & GOTM: a viewer
      # who cannot use it gets `data` without them (FeatureGate#can_use_feature?).
      def show
        limit = clamp_per(params[:limit], default_per: 10, max_per: 20)
        data = can_use_feature?(:voting_gotm) ? winners(limit) : {}

        render json: { data: data, meta: { limit: limit } }
      end

      private

      def winners(limit)
        # `images` stays on the eager_load and `platforms` goes through a
        # separate preload on purpose: putting two has_manys in one eager_load
        # joins them against each other, so the rows come back multiplied
        # images x platforms.
        gotm = GotmEntry
          .eager_load(game: :images)
          .preload(game: :platforms)
          .order(round_number: :desc, game_index: :asc)
          .limit(limit)
          .load_async

        nr_gotm = NrGotmEntry
          .eager_load(game: :images)
          .preload(game: :platforms)
          .order(round_number: :desc, game_index: :asc)
          .limit(limit)
          .load_async

        {
          gotm: GotmEntryResource.new(gotm, params: { include_game: true }).serializable_hash,
          nr_gotm: NrGotmEntryResource.new(nr_gotm, params: { include_game: true }).serializable_hash
        }
      end
    end
  end
end

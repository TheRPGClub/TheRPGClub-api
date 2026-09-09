# frozen_string_literal: true

module Api
  module V1
    class DashboardsController < ApplicationController
      def show
        limit = clamp_per(params[:limit], default_per: 10, max_per: 20)

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

        render json: {
          data: {
            gotm: GotmEntryResource.new(gotm, params: { include_game: true }).serializable_hash,
            nr_gotm: NrGotmEntryResource.new(nr_gotm, params: { include_game: true }).serializable_hash
          },
          meta: { limit: limit }
        }
      end
    end
  end
end

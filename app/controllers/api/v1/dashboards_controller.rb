# frozen_string_literal: true

module Api
  module V1
    class DashboardsController < ApplicationController
      def show
        limit = pagination_limit(default: 10, max: 20)

        gotm = GotmEntry
          .eager_load(game: :images)
          .order(round_number: :desc, game_index: :asc)
          .limit(limit)
          .load_async

        nr_gotm = NrGotmEntry
          .eager_load(game: :images)
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

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
            gotm: gotm.as_json,
            nr_gotm: nr_gotm.as_json
          },
          meta: { limit: limit }
        }
      end
    end
  end
end

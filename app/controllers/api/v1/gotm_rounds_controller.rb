# frozen_string_literal: true

module Api
  module V1
    # GOTM / NR-GOTM history grouped and paged by round (see Gotm::RoundHistory),
    # so clients don't group gotm_entries / nr_gotm_entries themselves. Read-only
    # and open to any authenticated caller.
    class GotmRoundsController < ApplicationController
      DEFAULT_PER = 12
      MAX_PER = 100

      # GET /api/v1/gotm_rounds?kind=&year=&q=&sort=&page=&per=
      #
      # Pages are rounds, not entries.
      def index
        kind = params[:kind].presence || "both"
        sort = params[:sort].presence || "desc"
        year = params[:year].presence && Integer(params[:year], 10, exception: false)
        return invalid_param("kind", Gotm::RoundHistory::KIND_PARAMS) unless Gotm::RoundHistory::KIND_PARAMS.include?(kind)
        return invalid_param("sort", Gotm::RoundHistory::SORTS) unless Gotm::RoundHistory::SORTS.include?(sort)
        if params[:year].present? && year.nil?
          return render json: { error: "invalid_year", message: "year must be an integer" }, status: :unprocessable_content
        end

        history = Gotm::RoundHistory.new(kind:, year:, query: params[:q])
        pagy, records = pagy(
          history.rounds_relation(sort:), count: history.round_count,
          **pagy_options(default_per: DEFAULT_PER, max_per: MAX_PER)
        )
        render json: {
          data: history.rounds(records.map(&:round_number)),
          meta: pagy_meta(pagy).merge(years: history.years)
        }
      end

      # GET /api/v1/gotm_rounds/current
      #
      # The latest round with GOTM winners plus that same round's NR-GOTM games
      # (the bot's `/gotm current`), not the round currently being voted on.
      def current
        number = Gotm::RoundHistory.latest_round_number or raise ActiveRecord::RecordNotFound, "no GOTM round exists"
        render json: { data: Gotm::RoundHistory.new.rounds([ number ]).first }
      end

      private

      def invalid_param(name, allowed)
        render json: { error: "invalid_#{name}", message: "#{name} must be one of: #{allowed.join(', ')}" },
          status: :unprocessable_content
      end
    end
  end
end

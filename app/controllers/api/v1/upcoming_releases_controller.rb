# frozen_string_literal: true

module Api
  module V1
    # The Release Calendar (spec #389, ticket #394): GameDB's Upcoming
    # Releases in calendar order (Gamedb::UpcomingReleases). Any signed-in
    # member, gated by the Release Calendar Feature; the bot's service token
    # is never stopped by the gate (its upcoming-release search uses this).
    class UpcomingReleasesController < ApplicationController
      feature :release_calendar

      MONTH_FORMAT = /\A(\d{4})-(\d{2})\z/

      # GET /api/v1/upcoming_releases?month=YYYY-MM&platform_id=&game_id=&per_game=next&page=&per=
      #
      # Without `month`, every Upcoming Release from today (UTC) on, TBA last;
      # with it, those placed in that calendar month, past or future.
      # `platform_id` keeps an entry with any Release on one of the platforms,
      # `game_id` limits to those games, `per_game=next` keeps each game's
      # earliest entry. Ids are repeated (`platform_id=1&platform_id=2` or
      # `platform_id[]=1&platform_id[]=2`) or comma-separated. A malformed
      # `month`, id or `per_game` is a 422.
      def index
        filters = filter_params
        return if performed?

        options = pagy_options(default_per: 50, max_per: 100)
        count, entries = Gamedb::UpcomingReleases.new(today: Time.current.utc.to_date, **filters)
          .page(page: options[:page], limit: options[:limit])

        render json: {
          data: UpcomingReleaseResource.new(entries).serializable_hash,
          meta: pagy_meta(Pagy::Offset.new(count: count, **options))
        }
      end

      private

      def filter_params
        month = month_param
        platform_ids = ids_param(:platform_id)
        game_ids = ids_param(:game_id)
        next_per_game = per_game_param
        return if performed?

        { month: month, platform_ids: platform_ids, game_ids: game_ids, next_per_game: next_per_game }
      end

      def month_param
        return nil if params[:month].blank?

        year, month = MONTH_FORMAT.match(params[:month].to_s)&.captures&.map(&:to_i)
        return Date.new(year, month, 1) if year && Date.valid_date?(year, month, 1)

        invalid("invalid_month", "month must be YYYY-MM")
      end

      # Ids may come repeated bare (`platform_id=1&platform_id=2`, OpenAPI's
      # exploded form), repeated as an array (`platform_id[]=1`) or
      # comma-separated, in any mix. Rails' `params` keeps only the last bare
      # repeat, so they are read from the raw query string.
      def ids_param(name)
        query = Rack::Utils.parse_query(request.query_string)
        values = [ name.to_s, "#{name}[]" ].flat_map { |key| Array(query[key]) }
          .flat_map { |value| value.to_s.split(",", -1) }.map(&:strip)
        return [] if values.all?(&:empty?)

        ids = values.map { |value| Integer(value, 10, exception: false) }
        return ids.uniq if ids.all? { |id| id&.positive? }

        invalid("invalid_#{name}", "#{name} must be one or more positive integer ids")
      end

      def per_game_param
        return false if params[:per_game].blank?
        return true if params[:per_game] == "next"

        invalid("invalid_per_game", "per_game must be next")
      end

      def invalid(error, message)
        render json: { error: error, message: message }, status: :unprocessable_content unless performed?
        nil
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    # IGDB discovery proxy (#122). Admin/service-only — searching consumes the
    # shared IGDB credential's rate budget and is part of the curator import
    # flow, so it's gated like POST /api/v1/games rather than open to every
    # authenticated caller.
    class IgdbController < ApplicationController
      before_action :require_admin_or_service!

      SEARCH_DEFAULT_LIMIT = 25

      # IGDB's multiquery bundles at most 10 sub-queries, so a multi-title search
      # may name at most this many titles in one request.
      MAX_QUERY_TERMS = 10

      # GET /api/v1/igdb/search?q=<title>  (or ?igdb_id=1234 / ?igdb_id=1,2,3)
      #
      # Two modes, selected by which param the caller passes: `igdb_id` does a
      # direct id lookup (the bot resolves ids it already has), otherwise `q`
      # runs a fuzzy title search (the web). Either accepts several values at
      # once — `igdb_id=1,2,3` or repeated `q[]=zelda&q[]=mario` (≤10, IGDB's
      # multiquery cap) — to seed a bulk import; multi-title hits fan out through
      # one IGDB multiquery and each candidate carries the `matched_query` it
      # came from. Every candidate is tagged with `already_imported` (a
      # gamedb_games row with that igdb_id exists) so the UI can offer "view" vs
      # "import". A blank `q` and an empty `igdb_id` both yield an empty list.
      def search
        if query_terms.size > MAX_QUERY_TERMS
          return render json: {
            error: "too_many_queries",
            message: "Search at most #{MAX_QUERY_TERMS} titles at once."
          }, status: :unprocessable_entity
        end

        results = igdb_candidates
        imported_ids = GamedbGame.where(igdb_id: results.map { |result| result[:igdb_id] }).pluck(:igdb_id).to_set

        render json: {
          data: results.map { |result| result.merge(already_imported: imported_ids.include?(result[:igdb_id])) }
        }
      rescue Igdb::Client::ConfigurationError => error
        render json: { error: "igdb_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Igdb::Client::RequestError => error
        render json: { error: "igdb_request_failed", message: error.message }, status: :bad_gateway
      end

      private

      def igdb_candidates
        client = Igdb::Client.new
        if igdb_ids.present?
          client.search_by_ids(igdb_ids, limit: search_limit(default: igdb_ids.size))
        elsif query_terms.many?
          client.multi_search(query_terms, limit: search_limit(default: SEARCH_DEFAULT_LIMIT))
        else
          client.search(query_terms.first, limit: search_limit(default: SEARCH_DEFAULT_LIMIT))
        end
      end

      # IGDB ids to look up directly, from `?igdb_id=1234`, a comma-separated
      # `?igdb_id=1,2,3`, or repeated `?igdb_id[]=1&igdb_id[]=2`. Non-integer
      # tokens are dropped so a stray value can't break the apicalypse query.
      def igdb_ids
        @igdb_ids ||= Array(params[:igdb_id])
          .flat_map { |value| value.to_s.split(",") }
          .filter_map { |token| Integer(token.strip, exception: false) }
      end

      # Title(s) to search, from a single `?q=zelda` or repeated
      # `?q[]=zelda&q[]=mario`. Not comma-split (game titles contain commas);
      # blank terms are dropped. More than one term fans out via #multi_search.
      def query_terms
        @query_terms ||= Array(params[:q]).map { |value| value.to_s.strip }.reject(&:blank?)
      end

      def search_limit(default:)
        (params[:per].presence || params[:limit].presence)&.to_i || default
      end
    end
  end
end

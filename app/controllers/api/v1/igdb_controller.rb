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

      # GET /api/v1/igdb/search?q=<title>
      #
      # Proxies an IGDB games title search and tags each candidate with
      # `already_imported` (a gamedb_games row with that igdb_id exists) so the
      # UI can offer "view" vs "import". A blank `q` yields an empty list.
      def search
        results = Igdb::Client.new.search(params[:q], limit: search_limit)
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

      def search_limit
        (params[:per].presence || params[:limit].presence)&.to_i || SEARCH_DEFAULT_LIMIT
      end
    end
  end
end

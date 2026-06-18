# frozen_string_literal: true

module Api
  module V1
    class RegionsController < ApplicationController
      def index
        scope = GamedbRegion.all
        # Exact lookup by internal region code (`Game.getRegionByCode`, #106),
        # e.g. `?code=NA`. Returns the paginated list shape (a single-element one)
        # so the index contract stays uniform.
        scope = scope.where(region_code: params[:code]) if params[:code].present?
        # Lookup by IGDB region id (`?igdb_id=...`, #106) against the internal
        # `igdb_region_id` column.
        scope = scope.where(igdb_region_id: params[:igdb_id]) if params[:igdb_id].present?

        render_collection(scope, resource: RegionResource, default_order: { region_name: :asc })
      end

      def show
        render json: { data: GamedbRegion.find(params[:id]).as_json }
      end
    end
  end
end

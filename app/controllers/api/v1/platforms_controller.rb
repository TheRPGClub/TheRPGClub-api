# frozen_string_literal: true

module Api
  module V1
    class PlatformsController < ApplicationController
      def index
        scope = GamedbPlatform.all
        scope = scope.where("platform_name ILIKE :term OR platform_code ILIKE :term", term: "%#{query}%") if params[:q].present?
        # Exact lookup by internal platform code (`Game.getPlatformByCode`, #106),
        # e.g. `?code=PS5`. Still returns the paginated list shape — a single-element
        # one — so the index contract stays uniform.
        scope = scope.where(platform_code: params[:code]) if params[:code].present?
        # Bulk-resolve IGDB platform ids (`Game.getPlatformsByIgdbIds`, #106):
        # `?igdb_ids[]=6&igdb_ids[]=48`. `?igdb_id=6` is the single-id convenience
        # form; both fold into one `IN (...)` filter.
        scope = scope.where(igdb_platform_id: igdb_ids) if igdb_ids.present?

        render_collection(scope, resource: PlatformResource, default_order: { platform_name: :asc })
      end

      def show
        render json: { data: GamedbPlatform.find(params[:id]).as_json }
      end

      private

      def query
        ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
      end

      # The requested IGDB platform ids from the array (`igdb_ids[]`) and the
      # single-id (`igdb_id`) forms, blanks dropped.
      def igdb_ids
        (Array(params[:igdb_ids]) + Array(params[:igdb_id])).compact_blank
      end
    end
  end
end

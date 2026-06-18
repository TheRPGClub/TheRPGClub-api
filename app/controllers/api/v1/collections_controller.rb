# frozen_string_literal: true

module Api
  module V1
    class CollectionsController < ApplicationController
      def index
        scope = filtered_collections(UserGameCollection.where(user_id: params[:user_id]))
        render_collection(scope.preload(:platform), resource: CollectionEntryResource, default_order: { created_at: :desc })
      end

      # GET /api/v1/games/:id/collections — every member's entry for one game
      # (the community-ownership view, #101). Mirrors completions#game_index:
      # game-scoped, embeds the owning user.
      def game_index
        scope = UserGameCollection.where(gamedb_game_id: params[:id]).preload(:platform, :user)
        render_collection(scope, resource: CollectionUserEntryResource, default_order: { created_at: :desc })
      end

      # GET /api/v1/users/:user_id/collections/platform_summary — per-platform
      # tallies for a user's collection (#101). Mirrors the bot's
      # `getOverviewForUser`: a total plus one row per platform (the no-platform
      # entries collapse into a single null-platform row), ordered by count desc
      # then platform name. A grouped aggregate, so the total comes from a
      # separate plain `COUNT(*)`.
      def platform_summary
        scope = UserGameCollection.where(user_id: params[:user_id])
        rows = scope
          .left_joins(:platform)
          .group("user_game_collections.platform_id", "gamedb_platforms.platform_name", "gamedb_platforms.platform_abbreviation")
          .select(
            "user_game_collections.platform_id AS platform_id",
            "gamedb_platforms.platform_name AS platform_name",
            "gamedb_platforms.platform_abbreviation AS platform_abbreviation",
            "COUNT(*) AS count"
          )
          .order(Arel.sql("COUNT(*) DESC, LOWER(COALESCE(gamedb_platforms.platform_name, 'Unknown')), user_game_collections.platform_id"))

        render json: {
          data: {
            total_count: scope.count,
            platform_counts: CollectionPlatformCountResource.new(rows).serializable_hash
          }
        }
      end

      def show
        record = UserGameCollection.includes(:platform).find(params[:id])
        render json: { data: CollectionEntryDetailResource.new(record).serializable_hash }
      end

      def create
        record = UserGameCollection.create!(request_data.merge("user_id" => params[:user_id]))
        render json: { data: CollectionEntryDetailResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = UserGameCollection.find(params[:id])
        record.update!(request_data)
        render json: { data: CollectionEntryDetailResource.new(record).serializable_hash }
      end

      def destroy
        UserGameCollection.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # Optional filters mirroring the bot's collection `searchEntries`
      # (RPGClub_GameDB#839): `q` partial-matches the game title, `platform`
      # partial-matches any of the platform name/abbreviation/code,
      # `ownership_type` is an exact match and `game_id` filters by
      # `gamedb_game_id`. Each present param ANDs in via a subquery (no joins, so
      # the paginated `meta.count` stays exact), matching the index-side
      # taxonomy-filter pattern in GamesController.
      def filtered_collections(scope)
        if params[:q].present?
          titles = GamedbGame.where("title ILIKE ?", "%#{sanitize_like(params[:q])}%").select(:game_id)
          scope = scope.where(gamedb_game_id: titles)
        end

        if params[:platform].present?
          term = "%#{sanitize_like(params[:platform])}%"
          platforms = GamedbPlatform
            .where("platform_name ILIKE :term OR platform_abbreviation ILIKE :term OR platform_code ILIKE :term", term: term)
            .select(:platform_id)
          scope = scope.where(platform_id: platforms)
        end

        scope = scope.where(ownership_type: params[:ownership_type]) if params[:ownership_type].present?
        scope = scope.where(gamedb_game_id: params[:game_id]) if params[:game_id].present?
        scope
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end
    end
  end
end

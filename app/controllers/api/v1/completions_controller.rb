# frozen_string_literal: true

module Api
  module V1
    class CompletionsController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserGameCompletion.where(user_id: params[:user_id]).preload(:game, :platform)
        render_collection(scope, resource: CompletionEntryResource, default_order: { completed_at: :desc, created_at: :desc })
      end

      def game_index
        scope = UserGameCompletion.where(gamedb_game_id: params[:id]).includes(:user)
        render_collection(scope, resource: CompletionUserEntryResource, default_order: { completed_at: :desc })
      end

      # Users ranked by total completion count (most first). Mirrors the bot's
      # `getCompletionLeaderboard`: active members only (`server_left_at IS
      # NULL`), with an optional `q` filter on game title. Paginated with the
      # standard page/per params. A grouped aggregate, so the count is computed
      # explicitly and handed to pagy (its grouped-count path would otherwise
      # collide with the `COUNT(*)` ordering).
      def leaderboard
        base = RpgClubUser.where(server_left_at: nil).joins(:game_completions)
        if params[:q].present?
          base = base.joins(game_completions: :game)
            .where("gamedb_games.title ILIKE ?", "%#{leaderboard_query}%")
        end

        count = base.distinct.count(:user_id)
        ranked = base
          .group("rpg_club_users.user_id", "rpg_club_users.username", "rpg_club_users.global_name")
          .select(
            "rpg_club_users.user_id AS user_id",
            "rpg_club_users.username AS username",
            "rpg_club_users.global_name AS global_name",
            "COUNT(user_game_completions.completion_id) AS completion_count"
          )
          .order(Arel.sql("COUNT(user_game_completions.completion_id) DESC, rpg_club_users.user_id ASC"))

        pagy, records = pagy(ranked, count: count, **pagy_options)
        render json: {
          data: CompletionLeaderboardEntryResource.new(records).serializable_hash,
          meta: pagy_meta(pagy)
        }
      end

      def show
        record = UserGameCompletion.includes(:game, :platform).find(params[:id])
        render json: { data: CompletionEntryResource.new(record).serializable_hash }
      end

      def create
        record = UserGameCompletion.create!(request_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: CompletionEntryResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = UserGameCompletion.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: CompletionEntryResource.new(record).serializable_hash }
      end

      def destroy
        UserGameCompletion.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def leaderboard_query
        ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameCompletion.find_by(completion_id: params[:id])&.user_id
      end
    end
  end
end

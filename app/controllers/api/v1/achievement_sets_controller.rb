# frozen_string_literal: true

module Api
  module V1
    # Achievement Sets (ADR 0001).
    # - `show` is the set page read for www (api-09), open to any signed-in
    #   principal; departed members, placeholder progress rows and removed
    #   Achievements the member never unlocked are excluded.
    # - `update` is the admin-only manual fix for a set's GameDB link, which
    #   Achievements::LinkSetToGame resolves best-effort and never overwrites.
    class AchievementSetsController < ApplicationController
      include AchievementReadParams

      before_action :require_admin!, only: %i[update]

      # The set and every non-removed Achievement in display order. With
      # `user_id`, each carries that member's Unlock state, the member's
      # progress row is included, and the removed Achievements they unlocked are
      # listed under `removed_achievements`. 404 when `user_id` is not an
      # active member.
      def show
        set = AchievementSet.includes(:game).find(params[:id])
        user = params[:user_id].presence && RpgClubUser.active.without_images.find(params[:user_id])

        achievements = set.achievements.order(Arel.sql("display_order ASC NULLS LAST, id ASC")).to_a
        unlocks = user ? UserAchievementUnlock.where(user_id: user.user_id, achievement_id: achievements.map(&:id)).index_by(&:achievement_id) : {}
        progress = user && Achievements::Reads.progress.find_by(user_id: user.user_id, achievement_set_id: set.id)
        active, removed = achievements.partition { |achievement| achievement.removed_at.nil? }
        removed.select! { |achievement| unlocks.key?(achievement.id) }

        achievement_params = {
          unlocks: unlocks,
          viewer_unlocked_ids: Achievements::Reads.viewer_unlocked_ids(viewer_id, achievements.map(&:id))
        }
        render json: {
          data: AchievementSetResource.new(set).serializable_hash.merge(
            "game" => set.game && GameSummaryResource.new(set.game).serializable_hash,
            "user" => user && UserSummaryResource.new(user).serializable_hash,
            "progress" => progress && SetProgressResource.new(progress).serializable_hash,
            "achievements" => SetAchievementResource.new(active, params: achievement_params).serializable_hash,
            "removed_achievements" => SetAchievementResource.new(removed, params: achievement_params).serializable_hash
          )
        }
      end

      # PATCH /api/v1/achievement_sets/:id
      # Body: { "data": { "game_id": <gamedb_games.game_id | null> } }
      def update
        set = AchievementSet.find(params[:id])
        data = request_data
        raise ActionController::ParameterMissing, "game_id" unless data.key?("game_id")

        game_id = data["game_id"].presence
        if game_id && !GamedbGame.exists?(game_id:)
          return render json: { error: "game not found" }, status: :unprocessable_entity
        end

        set.update!(game_id:)
        render json: { data: AchievementSetLinkResource.new(set).serializable_hash }
      end

      private

      # Admins only: a role_admin member or a dev. The service token is
      # refused, since links are a human judgement.
      def require_admin!
        return true if current_principal&.discord_user? &&
          (current_principal.dev? || RpgClubUser.where(user_id: current_principal.id, role_admin: true).exists?)

        render json: { error: "forbidden" }, status: :forbidden
        false
      end
    end
  end
end

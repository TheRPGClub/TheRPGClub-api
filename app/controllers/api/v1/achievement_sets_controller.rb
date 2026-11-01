# frozen_string_literal: true

module Api
  module V1
    # Achievement Sets. `show` is the set page read for www (api-09), open to
    # any signed-in principal; departed members, placeholder progress rows and
    # removed Achievements the member never unlocked are excluded.
    class AchievementSetsController < ApplicationController
      include AchievementReadParams

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
    end
  end
end

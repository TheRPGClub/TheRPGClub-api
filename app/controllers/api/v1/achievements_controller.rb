# frozen_string_literal: true

module Api
  module V1
    # Achievement Hub reads for www that are not scoped to one member's path:
    # the set page, the community feed and a GameDB game's showcase. Open to
    # any signed-in principal. Departed members, placeholder progress rows and
    # removed Achievements are excluded (Achievements::Reads).
    class AchievementsController < ApplicationController
      include AchievementReadParams

      # The set and every non-removed Achievement in display order. With
      # `user_id`, each carries that member's Unlock state, the member's
      # progress row is included, and the removed Achievements they unlocked are
      # listed under `removed_achievements`. 404 when `user_id` is not an
      # active member.
      def show_set
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

      # The community feed: `view=latest` (default) groups Unlocks into cards
      # per member + set + UTC day; `view=highlights` is one card per Highlight
      # Unlock. Both filter by `provider` and page through `page`/`per`.
      def feed
        query = Achievements::Feed.new(provider: enum_param(:provider, Achievements::Reads::PROVIDERS))
        if enum_param(:view, Achievements::Feed::VIEWS) == "highlights"
          pagy, unlocks = pagy(query.highlights, **pagy_options)
          unlocks = unlocks.to_a
          data = AchievementFeedHighlightResource.new(unlocks, params: viewer_params(unlocks).merge(
            users: query.users_by_id(unlocks.map(&:user_id))
          )).serializable_hash
        else
          pagy, rows = pagy(query.groups, count: query.group_count, **pagy_options)
          cards = query.cards(rows.to_a)
          data = AchievementFeedGroupResource.new(cards, params: viewer_params(cards.flat_map(&:unlocks))).serializable_hash
        end
        render json: { data: data, meta: pagy_meta(pagy) }
      end
    end
  end
end

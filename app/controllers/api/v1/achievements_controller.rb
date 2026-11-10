# frozen_string_literal: true

module Api
  module V1
    # Achievement Hub reads for www that are not scoped to one member's path:
    # the community feed and a GameDB game's showcase. Open to
    # any signed-in principal. Departed members, placeholder progress rows and
    # removed Achievements are excluded (Achievements::Reads).
    class AchievementsController < ApplicationController
      feature :achievement_hub

      include AchievementReadParams

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
          options = pagy_options
          count, rows = query.group_page(**options)
          pagy = Pagy::Offset.new(count: count, **options)
          cards = query.cards(rows)
          data = AchievementFeedGroupResource.new(cards, params: viewer_params(cards.flat_map(&:unlocks))).serializable_hash
        end
        render json: { data: data, meta: pagy_meta(pagy) }
      end

      # The Achievement Sets linked to a GameDB game, each with the active
      # members who completed it, the viewer's own progress and its
      # non-removed Achievements (with their active holders). Unpaginated: a
      # game has a handful of sets. A fixed number of queries, however many
      # sets and Achievements.
      def game_sets
        game = GamedbGame.without_images.find(params[:id])
        sets = game.achievement_sets.order(Arel.sql("provider ASC, LOWER(title) ASC NULLS LAST, id ASC")).to_a
        set_ids = sets.map(&:id)
        completed = Achievements::Reads.progress.where(achievement_set_id: set_ids).where.not(completed_at: nil)
          .order(:completed_at, :id).to_a
        viewer_progress = Achievements::Reads.progress.where(achievement_set_id: set_ids, user_id: viewer_id)
          .index_by(&:achievement_set_id)
        achievements = Achievement.active.where(achievement_set_id: set_ids)
          .order(Arel.sql("display_order ASC NULLS LAST, id ASC")).to_a
        achievement_ids = achievements.map(&:id)

        render json: {
          data: GameAchievementSetResource.new(sets, params: {
            completions: completed.group_by(&:achievement_set_id),
            users: RpgClubUser.without_images.where(user_id: completed.map(&:user_id).uniq).index_by(&:user_id),
            viewer_progress: viewer_progress,
            achievements: achievements.group_by(&:achievement_set_id),
            holders: holders_by_achievement(achievement_ids),
            viewer_unlocked_ids: Achievements::Reads.viewer_unlocked_ids(viewer_id, achievement_ids)
          }).serializable_hash
        }
      end

      private

      # { achievement_id => [user_id] } of the active members who unlocked
      # each, earliest Unlock first.
      def holders_by_achievement(achievement_ids)
        Achievements::Reads.unlocks.where(achievement_id: achievement_ids)
          .order("user_achievement_unlocks.unlocked_at", "user_achievement_unlocks.id")
          .pluck(:achievement_id, :user_id)
          .group_by(&:first)
          .transform_values { |pairs| pairs.map(&:last) }
      end
    end
  end
end

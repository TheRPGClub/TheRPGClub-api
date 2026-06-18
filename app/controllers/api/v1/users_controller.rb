# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :require_authentication!, only: %i[avatar profile_image]

      PREVIEW_LIMIT_DEFAULT = 10
      PREVIEW_LIMIT_MAX = 50

      # Canonical `has_platform` tokens mapped to the `social_platforms.label`
      # substrings they match (case-insensitively). This mirrors the Discord
      # bot's own `SOCIAL_MATCHERS` / `getMembersWithPlatforms` resolution
      # (RPGClub_GameDB) so a bot caller passing `steam`/`psn`/`xbl`/`nsw`
      # hits exactly the platforms it resolves locally. Any token not listed
      # here falls back to a literal case-insensitive label substring match.
      PLATFORM_LABEL_ALIASES = {
        "steam" => %w[steam],
        "psn" => %w[psn playstation],
        "xbl" => %w[xbox],
        "nsw" => %w[nintendo switch],
        "completionator" => %w[completionator]
      }.freeze

      def index
        scope = RpgClubUser.without_images
        scope = scope.where("username ILIKE :term OR global_name ILIKE :term OR user_id = :exact", term: "%#{query}%", exact: params[:q]) if params[:q].present?
        scope = scope.where(user_id: discord_ids) if discord_ids.present?

        if platform_tokens.present?
          scope = scope.where(user_id: UserSocial.where(platform_id: matching_platform_ids).select(:user_id))
            .includes(socials: :social_platform)
          render_collection(scope, resource: UserWithSocialsResource, default_order: { username: :asc })
        else
          render_collection(scope, resource: UserSummaryResource, default_order: { username: :asc })
        end
      end

      def show
        user = RpgClubUser.without_images.includes(socials: :social_platform).find(params[:user_id])
        limit = preview_limit

        previews = {
          now_playing: user.now_playing_entries.preload(:game, :platform).order(added_at: :desc).limit(limit).to_a,
          favorites:   user.game_favorites.preload(:game).order(:sort_order).limit(limit).to_a,
          reviews:     user.reviews.preload(:game).order(created_at: :desc).limit(limit).to_a,
          completions: user.game_completions.preload(:game, :platform).order(completed_at: :desc).limit(limit).to_a,
          journal:     UserGameJournalEntry.journaled_games_for(user.user_id).order(Arel.sql("last_entry_at DESC")).limit(limit).to_a
        }

        counts = {
          now_playing: user.now_playing_entries.count,
          favorites:   user.game_favorites.count,
          reviews:     user.reviews.count,
          completions: user.game_completions.count,
          backlog:     user.game_backlog_entries.count,
          collections: user.game_collections.count,
          journal:     user.journal_entries.distinct.count(:gamedb_game_id)
        }

        render json: {
          data: UserResource.new(user, params: previews.merge(counts: counts)).serializable_hash
        }
      end

      def avatar
        send_user_image("avatar_blob")
      end

      def profile_image
        send_user_image("profile_image")
      end

      private

      def query
        ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
      end

      # Exact Discord-snowflake match(es). `user_id` already *is* the Discord
      # snowflake on this schema, so this is an exact filter (no fuzzy username
      # match like `q`). Accepts a comma-separated list.
      def discord_ids
        @discord_ids ||= params[:discord_id].to_s.split(",").map(&:strip).reject(&:blank?)
      end

      # The `has_platform` filter tokens (comma-separated), lowercased.
      def platform_tokens
        @platform_tokens ||= params[:has_platform].to_s.split(",").map { |t| t.strip.downcase }.reject(&:blank?)
      end

      # The social platforms matching the requested `has_platform` tokens —
      # each token expanded to its alias substrings (or the literal token) and
      # matched case-insensitively against `label`. Returned as an id subquery
      # for `WHERE user_id IN (… user_socials …)` filtering.
      def matching_platform_ids
        patterns = platform_tokens
          .flat_map { |t| PLATFORM_LABEL_ALIASES.fetch(t, [ t ]) }
          .map { |p| "%#{ActiveRecord::Base.sanitize_sql_like(p)}%" }
        clause = Array.new(patterns.size, "label ILIKE ?").join(" OR ")
        SocialPlatform.where(clause, *patterns).select(:id)
      end

      def preview_limit
        raw = params[:preview_limit].to_i
        raw = PREVIEW_LIMIT_DEFAULT if raw <= 0
        [ raw, PREVIEW_LIMIT_MAX ].min
      end

      def send_user_image(column)
        data = RpgClubUser.select(column).find(params[:user_id]).public_send(column)
        return render(json: { error: "image_not_found" }, status: :not_found) if data.blank?

        send_data data, type: "image/png", disposition: "inline"
      end
    end
  end
end

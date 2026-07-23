# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :require_authentication!, only: %i[avatar profile_image]
      # Discord member-sync writes are service-only — only the bot's bearer
      # token may create/update users or bulk-mark departures (#105).
      before_action :require_service!, only: %i[upsert update mark_departed]

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
        scope = scope.where.not(emoji_name: nil) if has_emoji_name?

        if platform_tokens.present?
          scope = scope.where(user_id: UserSocial.where(platform_id: matching_platform_ids).select(:user_id))
            .includes(socials: :social_platform)
          render_collection(scope, resource: UserWithSocialsResource, default_order: { username: :asc })
        elsif has_emoji_name?
          # Surface `emoji_name` so UserEmojiService can detect display-name drift.
          render_collection(scope, resource: UserServiceResource, default_order: { username: :asc })
        else
          render_collection(scope, resource: UserSummaryResource, default_order: { username: :asc })
        end
      end

      def show
        user = RpgClubUser.without_images.includes(socials: :social_platform).find(params[:user_id])
        limit = preview_limit

        previews = {
          now_playing: user.now_playing_entries.with_now_playing_details.preload(:game, :platform).order(added_at: :desc).limit(limit).to_a,
          favorites:   user.game_favorites.preload(:game).order(:sort_order).limit(limit).to_a,
          reviews:     user.reviews.preload(:game).order(created_at: :desc).limit(limit).to_a,
          completions: user.game_completions.preload(:game, :platform).order(completed_at: :desc).limit(limit).to_a,
          journal:     UserGameJournalEntry.journaled_games_for(user.user_id).order(Arel.sql("last_entry_at DESC")).limit(limit).to_a
        }

        now_playing = user.now_playing_entries.async_count
        favorites   = user.game_favorites.async_count
        reviews     = user.reviews.async_count
        completions = user.game_completions.async_count
        backlog     = user.game_backlog_entries.async_count
        collections = user.game_collections.async_count
        journal     = user.journal_entries.distinct.async_count(:gamedb_game_id)

        counts = {
          now_playing: now_playing.value, favorites: favorites.value, reviews: reviews.value,
          completions: completions.value, backlog: backlog.value, collections: collections.value,
          journal: journal.value
        }

        render json: {
          data: UserResource.new(user, params: previews.merge(counts: counts)).serializable_hash
        }
      end

      # POST /api/v1/users/upsert
      #
      # Creates or updates a user keyed by `discord_id`. Called on guild member
      # join/update events and by the `memberscan` admin command. Only the
      # listed columns are writable; passing `server_left_at: null` clears a
      # prior departure (a rejoin). 201 when a new row was created, 200 on
      # update. (#105)
      def upsert
        discord_id = request_data["discord_id"].presence
        return render(json: { error: "discord_id is required" }, status: :unprocessable_entity) if discord_id.blank?

        user = RpgClubUser.find_or_initialize_by(user_id: discord_id.to_s)
        user.assign_attributes(request_data.slice("username", "global_name", "is_bot", "server_joined_at", "server_left_at"))
        user.save!

        render json: { data: UserServiceResource.new(user).serializable_hash },
          status: user.previously_new_record? ? :created : :ok
      end

      # PATCH/PUT /api/v1/users/:user_id
      #
      # Updates the service-managed fields the bot owns. The bot's logical names
      # map onto the schema: `last_seen` -> `last_seen_at`, and `departed`
      # (boolean) toggles `server_left_at` — true stamps a departure (preserving
      # an existing one), false clears it (a rejoin). `emoji_name` is set/cleared
      # by UserEmojiService. (#105)
      def update
        user = RpgClubUser.find(params[:user_id])
        data = request_data

        user.emoji_name = data["emoji_name"] if data.key?("emoji_name")
        user.last_seen_at = data["last_seen"] if data.key?("last_seen")
        if data.key?("departed")
          departed = ActiveModel::Type::Boolean.new.cast(data["departed"])
          user.server_left_at = departed ? (user.server_left_at || Time.current) : nil
        end

        user.save!
        render json: { data: UserServiceResource.new(user).serializable_hash }
      end

      # POST /api/v1/users/mark_departed
      #
      # Bulk-marks every active user NOT in the supplied `active_ids` list as
      # departed (stamps `server_left_at`), mirroring the bot's `memberscan`
      # reconciliation. Already-departed rows (`server_left_at` set) are left
      # untouched so the original departure time is preserved. Returns the count
      # of rows newly marked. An empty list is rejected — it would mark every
      # member departed. (#105)
      def mark_departed
        ids = active_ids
        return render(json: { error: "active_ids must be a non-empty array" }, status: :unprocessable_entity) if ids.empty?

        count = RpgClubUser
          .where(server_left_at: nil)
          .where.not(user_id: ids)
          .update_all(server_left_at: Time.current, updated_at: Time.current)

        render json: { count: count }
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

      # Whether the `has_emoji_name` filter is on (returns only users whose
      # `emoji_name` is set). Accepts the usual truthy tokens (`true`/`1`/…).
      def has_emoji_name?
        ActiveModel::Type::Boolean.new.cast(params[:has_emoji_name])
      end

      # The active Discord ids for #mark_departed. Accepts the list at the top
      # level (`active_ids`) or nested under the `data` envelope; normalizes to
      # a de-duped array of non-blank id strings.
      def active_ids
        raw = params[:active_ids]
        raw = params.dig(:data, :active_ids) if raw.blank?
        Array(raw).map { |v| v.to_s.strip }.reject(&:blank?).uniq
      end

      # The `has_platform` filter tokens (comma-separated), lowercased.
      def platform_tokens
        @platform_tokens ||= params[:has_platform].to_s.split(",").map { |t| t.strip.downcase }.reject(&:blank?)
      end

      # The social platforms matching the requested `has_platform` tokens —
      # each token expanded to its alias substrings (or the literal token) and
      # matched case-insensitively against `label`. Returned as an id subquery
      # for `WHERE user_id IN (… user_socials …)` filtering. The patterns are
      # `LIKE`-escaped and bound (`ILIKE ANY (ARRAY[?])`), so no user input
      # reaches the SQL string.
      def matching_platform_ids
        patterns = platform_tokens
          .flat_map { |t| PLATFORM_LABEL_ALIASES.fetch(t, [ t ]) }
          .map { |p| "%#{ActiveRecord::Base.sanitize_sql_like(p)}%" }
        SocialPlatform.where("label ILIKE ANY (ARRAY[?])", patterns).select(:id)
      end

      def preview_limit
        raw = params[:preview_limit].to_i
        raw = PREVIEW_LIMIT_DEFAULT if raw <= 0
        [ raw, PREVIEW_LIMIT_MAX ].min
      end

      def send_user_image(column)
        user = RpgClubUser.select(column, :updated_at).find(params[:user_id])
        data = user.public_send(column)
        return render(json: { error: "image_not_found" }, status: :not_found) if data.blank?

        # Cache aggressively: without these headers every route change on the
        # website re-fetched every rendered avatar (Rails defaults to
        # max-age=0), and a burst of multi-second blob streams occupied all
        # Puma threads until /up missed the Fly health check and the proxy
        # pulled the only machine (2026-07-23 09:24 UTC outage). The ETag is
        # content-based (not just updated_at, which churns on every
        # last-seen sync) so revalidations after expiry 304 instead of
        # re-streaming an unchanged blob. Endpoint is unauthenticated, so
        # `public` is safe for shared caches.
        expires_in 1.day, public: true
        return unless stale?(etag: data, last_modified: user.updated_at)

        send_data data, type: "image/png", disposition: "inline"
      end
    end
  end
end

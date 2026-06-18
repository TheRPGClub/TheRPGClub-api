# frozen_string_literal: true

module Api
  module V1
    # Per-game journal feature (bot parity, #39). Entries belong to a
    # (user, game) pair and are all public — there is no visibility concept.
    class JournalController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      # GET /api/v1/users/:user_id/journal
      #
      # The games a user has journaled, with per-game entry counts and the
      # last-entry timestamp, ordered by game title. One row per game (entries
      # are collapsed into a count), paginated like every other collection.
      #
      # Optional filters narrow which games appear (#103): `game_id` restricts
      # to a single game, and `q` keeps only games where the user has at least
      # one entry whose `entry_title`/`entry_body` matches (case-insensitive
      # substring). The per-game `entry_count`/`last_entry_at` stay the full
      # per-game totals — `q` selects the games, it does not re-scope the
      # aggregates. Cross-user / entry-level text search lives on the separate
      # `journal#search` endpoint.
      def index
        # The (optionally filtered) set of the user's entries drives both which
        # games appear and the page count, so the two never disagree. Restricting
        # the grid by `game_id IN (matching entries)` rather than joining the
        # filter in keeps the per-game `COUNT(*)`/`MAX` aggregates the full
        # totals — `q` selects the games, it does not re-scope the aggregates.
        entries = filtered_entries(params[:user_id])
        scope = UserGameJournalEntry.journaled_games_for(params[:user_id])
          .where(game_id: entries.select(:gamedb_game_id))
          .order(Arel.sql("gamedb_games.title ASC, gamedb_games.game_id ASC"))

        # The grouped scope's `.count` returns a per-group hash, so hand pagy an
        # explicit count of the distinct journaled games (filtered the same way).
        count = entries.distinct.count(:gamedb_game_id)
        pagy, games = pagy(scope, count: count, **pagy_options)

        render json: { data: JournaledGameResource.new(games).serializable_hash, meta: pagy_meta(pagy) }
      end

      # GET /api/v1/users/:user_id/journal/status?game_ids[]=1&game_ids[]=2
      #
      # The user's per-game journal status for a requested set of game ids:
      # entry count + last-entry timestamp, one row per game that has entries.
      # Mirrors the bot's `getJournalStatusForGames`; powers the journal
      # badge/count in the game-completion list. Games with no entries are
      # omitted (the caller treats a missing id as a zero count). Not paginated
      # — the caller passes a bounded set of ids (one page of games).
      def status
        game_ids = Array(params[:game_ids]).map(&:to_i).reject(&:zero?).uniq
        rows =
          if game_ids.empty?
            []
          else
            UserGameJournalEntry
              .where(user_id: params[:user_id], gamedb_game_id: game_ids)
              .group(:gamedb_game_id)
              .select("gamedb_game_id, COUNT(*) AS entry_count, MAX(created_at) AS last_entry_at")
          end

        render json: { data: JournalStatusResource.new(rows).serializable_hash }
      end

      # GET /api/v1/journal_entries/contributors
      #
      # Users with at least one journal entry, each with their distinct
      # journaled-game count and total entry count, most-journaled first.
      # Mirrors the bot's `getAllJournalUsers`: bots and members who have left
      # the server are excluded (`is_bot = false AND server_left_at IS NULL`).
      # Paginated like every other collection. A grouped aggregate, so the count
      # is computed explicitly and handed to pagy (its grouped-count path would
      # otherwise collide with the `COUNT(*)` ordering).
      def contributors
        base = RpgClubUser.where(is_bot: false, server_left_at: nil).joins(:journal_entries)

        count = base.distinct.count(:user_id)
        ranked = base
          .group("rpg_club_users.user_id", "rpg_club_users.username", "rpg_club_users.global_name")
          .select(
            "rpg_club_users.user_id AS user_id",
            "rpg_club_users.username AS username",
            "rpg_club_users.global_name AS global_name",
            "COUNT(DISTINCT user_game_journal_entries.gamedb_game_id) AS game_count",
            "COUNT(user_game_journal_entries.entry_id) AS entry_count"
          )
          .order(Arel.sql(
            "COUNT(DISTINCT user_game_journal_entries.gamedb_game_id) DESC, " \
            "rpg_club_users.global_name ASC NULLS LAST, " \
            "rpg_club_users.username ASC NULLS LAST, " \
            "rpg_club_users.user_id ASC"
          ))

        pagy, records = pagy(ranked, count: count, **pagy_options)
        render json: {
          data: JournalContributorResource.new(records).serializable_hash,
          meta: pagy_meta(pagy)
        }
      end

      # GET /api/v1/journal_entries?q=...&game_id=...&user_id=...
      #
      # Cross-user journal entry search, each entry carrying its embedded game
      # and author. Mirrors the bot's `searchJournalEntries`: `q` is a
      # case-insensitive substring over `entry_title`/`entry_body`, with optional
      # `game_id` and `user_id` filters (the `user_id` filter is what serves the
      # bot's per-author search — the user-scoped grid endpoint cannot return
      # entries). All entries are public, so there is no visibility filtering.
      # Ordered `created_at DESC, entry_id DESC` and paginated.
      def search
        scope = UserGameJournalEntry.includes(:game, :user)
        if params[:q].present?
          like = "%#{sanitize_like(params[:q])}%"
          scope = scope.where("entry_title ILIKE :q OR entry_body ILIKE :q", q: like)
        end
        scope = scope.where(gamedb_game_id: params[:game_id]) if params[:game_id].present?
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

        render_collection(scope, resource: JournalEntryGameUserResource,
          default_order: { created_at: :desc, entry_id: :desc })
      end

      # GET /api/v1/games/:id/journal
      #
      # Journal entries for a game across users. An optional `user_id` query
      # param narrows to a single author.
      def game_index
        scope = UserGameJournalEntry.where(gamedb_game_id: params[:id]).includes(:user)
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

        render_collection(scope, resource: JournalEntryUserResource,
          default_order: { created_at: :desc, entry_id: :desc })
      end

      # GET /api/v1/journal_entries/:id
      def show
        record = UserGameJournalEntry.includes(:game).find(params[:id])
        render json: { data: JournalEntryGameResource.new(record).serializable_hash }
      end

      # POST /api/v1/users/:user_id/journal
      def create
        record = UserGameJournalEntry.create!(request_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: JournalEntryGameResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/journal_entries/:id
      def update
        record = UserGameJournalEntry.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: JournalEntryGameResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/journal_entries/:id
      def destroy
        UserGameJournalEntry.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # The user's journal entries, narrowed by the optional `game_id`/`q`
      # grid filters (#103). Used both as the `game_id IN (…)` subquery that
      # picks which games show and as the source of the distinct-game page
      # count, so the grid and its `meta.count` always agree.
      def filtered_entries(user_id)
        scope = UserGameJournalEntry.where(user_id: user_id)
        scope = scope.where(gamedb_game_id: params[:game_id]) if params[:game_id].present?

        if params[:q].present?
          scope = scope.where("entry_title ILIKE :q OR entry_body ILIKE :q", q: "%#{sanitize_like(params[:q])}%")
        end

        scope
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameJournalEntry.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    # Scheduled release announcements (bot parity, #43, #109). Each row is the
    # bot's plan to announce a single GamedbRelease at `announce_at`; the row is
    # keyed by `release_id` (1:1 with the release), so the member `:id` is a
    # release_id.
    #
    # As the bot's GameReleaseAnnouncementService migrates off direct SQL (#109),
    # the heavy lifting lives server-side here: #due returns the canonical, due,
    # not-yet-released candidates (and auto-marks any whose window has already
    # passed), and #sync rebuilds a game's schedule from its releases and applies
    # the canonicality rules. The delivery columns (`sent_at`, `skipped_at`,
    # `skip_reason`) are admin/service-writable so the bot can mark an
    # announcement sent/missed via PATCH; the #skip action remains a convenience
    # for the skip-only path. Reads of #due are service-only (the bot's poll);
    # the writes are admin/service-gated.
    class ReleaseAnnouncementsController < ApplicationController
      before_action :require_service!, only: %i[due]
      before_action :require_admin_or_service!, only: %i[create update destroy skip sync]

      # Skip reasons shared with the bot (GameReleaseAnnouncement.ts). `port-only`
      # / `same-day` are the canonicality skips applied by #sync; the missed-window
      # reason is stamped by #due once a release's announce window has lapsed.
      PORT_ONLY_RELEASE_REASON = "port-only-release"
      SAME_DAY_DUPLICATE_REASON = "same-day-platform-duplicate"
      MISSED_WINDOW_REASON = "release-window-missed"

      DEFAULT_DUE_LIMIT = 25
      MAX_DUE_LIMIT = 100

      # Region whose Releases only become canonical when a game has no other
      # (ADR 0009): announcements go out for the release most members get.
      JAPAN_REGION_CODE = "JP"

      # Every exact-day Release ranked for canonicality within its game: only
      # Date Precision `day` is announced (api#392), so a vague or TBA Release
      # is never a candidate, never skipped, and never shifts the canonical
      # date. The canonical Release (`canonical_rank` 1) is the earliest outside
      # Japan, or the earliest Japanese one when the game has nothing else, with
      # the lowest `release_id` breaking a same-day tie. `canonical_date` is that
      # Release's date, so the others can be told apart as same-day duplicates
      # (any region, Japan included) or port-only Releases (any other date).
      # Split around its WHERE clause so #sync can narrow it to one game.
      RANKED_RELEASES_SELECT_SQL = <<~SQL.squish
        SELECT r.release_id,
               r.release_date,
               FIRST_VALUE(r.release_date) OVER canonical_order AS canonical_date,
               ROW_NUMBER() OVER canonical_order AS canonical_rank
        FROM gamedb_releases r
        JOIN gamedb_regions g ON g.region_id = r.region_id
        WHERE r.date_precision = 'day'
      SQL
      RANKED_RELEASES_WINDOW_SQL = <<~SQL.squish
        WINDOW canonical_order AS (
          PARTITION BY r.game_id
          ORDER BY (g.region_code = '#{JAPAN_REGION_CODE}') ASC, r.release_date ASC, r.release_id ASC
        )
      SQL

      # Canonical release per game across every game, used as the
      # `release_id IN (…)` filter on #due.
      CANONICAL_RELEASE_IDS_SQL = <<~SQL.squish
        SELECT ranked.release_id
        FROM (#{RANKED_RELEASES_SELECT_SQL} #{RANKED_RELEASES_WINDOW_SQL}) ranked
        WHERE ranked.canonical_rank = 1
      SQL

      # A game is announced once (ADR 0009). Its sent announcement lives on the
      # announced Release, and `gamedb_games.release_announced_at` keeps it
      # when an IGDB refresh removes that Release. Either one keeps every other
      # Release of the game out of #due.
      GAME_ALREADY_ANNOUNCED_SQL = <<~SQL.squish
        gamedb_games.release_announced_at IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM gamedb_releases announced
          JOIN gamedb_release_announcements sent ON sent.release_id = announced.release_id
          WHERE announced.game_id = gamedb_releases.game_id
            AND sent.sent_at IS NOT NULL
        )
      SQL

      # GET /api/v1/games/:id/release_announcements
      def game_index
        scope = GamedbReleaseAnnouncement
          .joins(:release)
          .where(gamedb_releases: { game_id: params[:id] })
        render_collection(scope, resource: ReleaseAnnouncementResource, default_order: { announce_at: :asc, release_id: :asc })
      end

      # GET /api/v1/release_announcements/due
      #
      # Service-only poll endpoint (the bot's `listDueAnnouncements`). Returns the
      # announcements that are ready to post: not yet sent or skipped, whose
      # `announce_at` has passed, whose release is still in the future, and which
      # are the canonical release for their game. The bot fires this every tick,
      # so the missed-window sweep (`markMissedAnnouncements`) is folded in
      # server-side: any pending announcement whose release has already shipped is
      # stamped skipped first, so it never appears here. Unpaginated; bounded by
      # `limit` (default 25, max 100).
      def due
        now = Time.current
        mark_missed_announcements(now)

        render json: { data: DueReleaseAnnouncementResource.new(due_scope(now).limit(due_limit)).serializable_hash }
      end

      # GET /api/v1/release_announcements/:id  (id is the release_id)
      def show
        record = GamedbReleaseAnnouncement.find(params[:id])
        render json: { data: ReleaseAnnouncementResource.new(record).serializable_hash }
      end

      # POST /api/v1/release_announcements
      #
      # Schedules an announcement for a release. The body carries `release_id`
      # (the PK/FK) and `announce_at`.
      def create
        record = GamedbReleaseAnnouncement.create!(request_data)
        record.reload
        render json: { data: ReleaseAnnouncementResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/release_announcements/:id
      #
      # Reschedules a pending announcement (`announce_at`) and/or marks delivery
      # state: the bot PATCHes `sent_at` to mark an announcement sent, or
      # `skipped_at` + `skip_reason` to mark it missed (#109). Admin/service-gated.
      def update
        record = GamedbReleaseAnnouncement.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: ReleaseAnnouncementResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/release_announcements/:id
      def destroy
        GamedbReleaseAnnouncement.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      # POST /api/v1/release_announcements/:id/skip
      #
      # Marks an announcement skipped so the bot won't send it: stamps
      # `skipped_at` now and stores the optional `skip_reason`.
      def skip
        record = GamedbReleaseAnnouncement.find(params[:id])
        record.update!(skipped_at: Time.current, skip_reason: skip_reason)
        record.reload
        render json: { data: ReleaseAnnouncementResource.new(record).serializable_hash }
      end

      # PATCH/PUT /api/v1/games/:id/release_announcements
      #
      # Admin/service-only. Rebuilds the game's announcement schedule from its
      # releases and applies canonicality (the bot's `syncReleaseAnnouncements` +
      # `markNonCanonicalAnnouncements`). Server-side and body-less — everything is
      # computed from `gamedb_releases`. Runs three steps, scoped to the path game,
      # in one transaction:
      #   1. upsert: for every release with a `release_date`, schedule
      #      `announce_at = release_date - 7 days` (insert, or move a pending row
      #      whose time changed; rows already sent/skipped are left alone)
      #   2. restore: clear the canonicality skip on rows that were skipped as
      #      port-only / same-day-duplicate but no longer qualify
      #   3. mark: skip rows that are now non-canonical (`port-only-release` for a
      #      later release date, `same-day-platform-duplicate` for a same-day tie)
      # Returns the row counts written by each step.
      def sync
        game_id = params[:id].to_i
        result = {}

        GamedbReleaseAnnouncement.transaction do
          result[:upserted] = upsert_announcements(game_id)
          result[:restored] = restore_non_canonical(game_id)
          result[:skipped]  = mark_non_canonical(game_id)
        end

        render json: { data: result }
      end

      private

      # The due feed (unbounded). Pending (`sent_at`/`skipped_at` NULL),
      # already-announceable (`announce_at <= now`), still-upcoming
      # (`release_date` after today, UTC) announcements that are the canonical
      # release for their game, for games not already announced, ordered the
      # same way the bot's `listDueAnnouncements` orders.
      # Projected onto the joined release/game/platform columns the bot needs.
      def due_scope(now)
        GamedbReleaseAnnouncement
          .joins(:release)
          .joins("JOIN gamedb_games ON gamedb_games.game_id = gamedb_releases.game_id")
          .joins("LEFT JOIN gamedb_platforms ON gamedb_platforms.platform_id = gamedb_releases.platform_id")
          .where(sent_at: nil, skipped_at: nil)
          .where("gamedb_release_announcements.announce_at <= :now", now: now)
          .where("gamedb_releases.release_date > :today", today: now.utc.to_date)
          .where("gamedb_release_announcements.release_id IN (#{CANONICAL_RELEASE_IDS_SQL})")
          .where.not(GAME_ALREADY_ANNOUNCED_SQL)
          .select(
            "gamedb_release_announcements.release_id AS release_id",
            "gamedb_releases.game_id AS game_id",
            "gamedb_games.title AS title",
            "gamedb_releases.release_date AS release_date",
            "gamedb_release_announcements.announce_at AS announce_at",
            "gamedb_platforms.platform_name AS platform_name",
            "gamedb_platforms.platform_abbreviation AS platform_abbreviation",
            "gamedb_games.igdb_url AS igdb_url"
          )
          .order(Arel.sql(
            "gamedb_release_announcements.announce_at ASC, gamedb_releases.release_date ASC, " \
            "gamedb_releases.game_id ASC, gamedb_release_announcements.release_id ASC"
          ))
      end

      # Optional reason supplied with a skip; `nil` when none was sent.
      def skip_reason
        params.dig(:data, :skip_reason).presence
      end

      # Requested page size for #due, clamped to [1, 100] with a default of 25 —
      # mirrors the bot's `clampBatchSize`.
      def due_limit
        raw = params[:limit].to_i
        return DEFAULT_DUE_LIMIT if raw <= 0

        [ raw, MAX_DUE_LIMIT ].min
      end

      # Step 1 of #sync. Upsert announcements for every exact-day (Date
      # Precision `day`) release of the game, scheduling `announce_at =
      # release_date - 7 days` (UTC midnight). On conflict (release_id PK) only a
      # pending row whose time actually changed is moved — rows the send loop
      # already owns (`sent_at`/`skipped_at` set) are never touched.
      def upsert_announcements(game_id)
        exec_update(<<~SQL.squish)
          INSERT INTO gamedb_release_announcements
            (release_id, announce_at, sent_at, skipped_at, skip_reason, created_at, updated_at)
          SELECT r.release_id, r.release_date - INTERVAL '7 days', NULL, NULL, NULL,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM gamedb_releases r
           WHERE r.date_precision = 'day'
             AND r.game_id = #{game_id}
          ON CONFLICT (release_id) DO UPDATE SET
            announce_at = EXCLUDED.announce_at,
            updated_at = CURRENT_TIMESTAMP
          WHERE gamedb_release_announcements.sent_at IS NULL
            AND gamedb_release_announcements.skipped_at IS NULL
            AND gamedb_release_announcements.announce_at <> EXCLUDED.announce_at
        SQL
      end

      # Step 2 of #sync. Clear the canonicality skip on the game's rows that were
      # skipped as port-only / same-day-duplicate but no longer qualify as
      # non-canonical. The `release_id IN (…this game…)` guard is required: the
      # `NOT EXISTS` is over this game's ranked releases only, so without it a
      # different game's skip would falsely qualify for restore.
      def restore_non_canonical(game_id)
        exec_update(<<~SQL.squish)
          UPDATE gamedb_release_announcements
             SET skipped_at = NULL,
                 skip_reason = NULL,
                 updated_at = CURRENT_TIMESTAMP
           WHERE sent_at IS NULL
             AND skip_reason IN (#{quote(PORT_ONLY_RELEASE_REASON)}, #{quote(SAME_DAY_DUPLICATE_REASON)})
             AND release_id IN (SELECT release_id FROM gamedb_releases WHERE game_id = #{game_id})
             AND NOT EXISTS (
               SELECT 1
               FROM (#{ranked_releases_sql(game_id)}) ranked
               WHERE ranked.canonical_rank > 1
                 AND ranked.release_id = gamedb_release_announcements.release_id
             )
        SQL
      end

      # Step 3 of #sync. Skip the game's now-non-canonical rows:
      # `same-day-platform-duplicate` for a Release on the canonical Release's
      # date (any platform or region), `port-only-release` for any other date,
      # including a Japanese Release earlier than a canonical one outside
      # Japan. `src` is the game's ranked non-canonical releases, so the join
      # self-scopes to this game; only pending rows are touched.
      def mark_non_canonical(game_id)
        exec_update(<<~SQL.squish)
          UPDATE gamedb_release_announcements a
             SET skipped_at = CURRENT_TIMESTAMP,
                 skip_reason = src.skip_reason,
                 updated_at = CURRENT_TIMESTAMP
            FROM (
              SELECT ranked.release_id,
                     CASE WHEN ranked.release_date = ranked.canonical_date
                          THEN #{quote(SAME_DAY_DUPLICATE_REASON)}
                          ELSE #{quote(PORT_ONLY_RELEASE_REASON)} END AS skip_reason
              FROM (#{ranked_releases_sql(game_id)}) ranked
              WHERE ranked.canonical_rank > 1
            ) src
           WHERE a.release_id = src.release_id
             AND a.sent_at IS NULL
             AND a.skipped_at IS NULL
        SQL
      end

      # Fold the bot's `markMissedAnnouncements` into #due: stamp any pending
      # announcement whose window has already passed (its release has shipped) as
      # skipped with `release-window-missed`, so it drops out of the due feed.
      def mark_missed_announcements(now)
        exec_update(<<~SQL.squish)
          UPDATE gamedb_release_announcements
             SET skipped_at = #{quote(now)},
                 skip_reason = #{quote(MISSED_WINDOW_REASON)},
                 updated_at = CURRENT_TIMESTAMP
           WHERE sent_at IS NULL
             AND skipped_at IS NULL
             AND announce_at <= #{quote(now)}
             AND EXISTS (
               SELECT 1 FROM gamedb_releases r
               WHERE r.release_id = gamedb_release_announcements.release_id
                 AND r.release_date <= #{quote(now.utc.to_date)}
             )
        SQL
      end

      # The game's releases ranked for canonicality (RANKED_RELEASES_*_SQL).
      # Scoped to the game; the window partitions are by `game_id`, so
      # restricting the rows here yields the same ranks as the global query
      # #due uses for this game.
      def ranked_releases_sql(game_id)
        "#{RANKED_RELEASES_SELECT_SQL} AND r.game_id = #{Integer(game_id)} #{RANKED_RELEASES_WINDOW_SQL}"
      end

      def exec_update(sql)
        GamedbReleaseAnnouncement.connection.exec_update(sql)
      end

      def quote(value)
        GamedbReleaseAnnouncement.connection.quote(value)
      end
    end
  end
end

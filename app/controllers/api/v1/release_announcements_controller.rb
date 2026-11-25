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

      # Stamped by #due once a release's announce window has lapsed. The
      # canonicality skips live in Gamedb::ReleaseAnnouncementSchedule.
      MISSED_WINDOW_REASON = "release-window-missed"

      DEFAULT_DUE_LIMIT = 25
      MAX_DUE_LIMIT = 100

      # A game is announced once (ADR 0010). Its sent announcement lives on the
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
      #
      # Until the next pending announcement comes due it answers `[]` from
      # Gamedb::DueAnnouncementGate without touching the database, so the
      # hourly poll lets Neon sleep. A query that finds nothing ready records
      # when the next one is; one that finds some leaves the gate open until
      # they are sent or skipped.
      def due
        now = Time.current
        return render(json: { data: [] }) unless Gamedb::DueAnnouncementGate.due?(now)

        mark_missed_announcements(now)
        rows = due_scope(now).limit(due_limit).to_a
        if rows.empty?
          Gamedb::DueAnnouncementGate.record(next_pending_announce_at(now), now)
        else
          Gamedb::DueAnnouncementGate.clear
        end

        render json: { data: DueReleaseAnnouncementResource.new(rows).serializable_hash }
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
      # releases and applies canonicality (Gamedb::ReleaseAnnouncementSchedule:
      # upsert, restore, mark), in one transaction. Body-less: everything is
      # computed from `gamedb_releases`. An IGDB refresh runs the same steps,
      # so this is the bot's catch-up for Releases changed any other way.
      # Returns the row counts written by each step.
      def sync
        result = GamedbReleaseAnnouncement.transaction do
          Gamedb::ReleaseAnnouncementSchedule.call(params[:id].to_i)
        end

        render json: { data: result.to_h }
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
          .where("gamedb_release_announcements.release_id IN (#{Gamedb::ReleaseAnnouncementSchedule::CANONICAL_RELEASE_IDS_SQL})")
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

      # When the next pending announcement becomes announceable. Pending ones
      # already past their time but not offered (non-canonical, or their game
      # was announced) are left to the missed-window sweep at the next query.
      def next_pending_announce_at(now)
        GamedbReleaseAnnouncement.where(sent_at: nil, skipped_at: nil)
          .where("announce_at > ?", now).minimum(:announce_at)
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

      def exec_update(sql)
        GamedbReleaseAnnouncement.connection.exec_update(sql)
      end

      def quote(value)
        GamedbReleaseAnnouncement.connection.quote(value)
      end
    end
  end
end

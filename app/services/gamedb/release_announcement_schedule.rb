# frozen_string_literal: true

module Gamedb
  # One game's release-announcement schedule, rebuilt from its Releases (the
  # bot's `syncReleaseAnnouncements` + `markNonCanonicalAnnouncements`, #109;
  # ADR 0009). Run by PATCH /games/:id/release_announcements and at the end of
  # every in-place IGDB refresh (Gamedb::ReleaseSync), so the weekly refresh
  # schedules and re-ranks announcements without waiting for the bot.
  #
  # Three steps, scoped to the game:
  #   1. upsert: every `day` Release gets `announce_at = release_date - LEAD`
  #      (insert, or move a pending row whose time changed; rows already
  #      sent or skipped are left alone);
  #   2. restore: clear the canonicality skip on rows that were skipped as
  #      port-only / same-day-duplicate but no longer qualify;
  #   3. mark: skip rows that are now non-canonical (`port-only-release` for
  #      another date, `same-day-platform-duplicate` for the canonical date).
  #
  # Callers own the transaction.
  class ReleaseAnnouncementSchedule
    # A release announcement goes out this long before its Release's date.
    LEAD = 7.days

    # Skip reasons shared with the bot (GameReleaseAnnouncement.ts).
    PORT_ONLY_RELEASE_REASON = "port-only-release"
    SAME_DAY_DUPLICATE_REASON = "same-day-platform-duplicate"

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
    # Split around its WHERE clause so a single game can be ranked.
    RANKED_RELEASES_SELECT_SQL = <<~SQL.squish
      SELECT r.release_id,
             r.release_date,
             FIRST_VALUE(r.release_date) OVER canonical_order AS canonical_date,
             ROW_NUMBER() OVER canonical_order AS canonical_rank
      FROM gamedb_releases r
      JOIN gamedb_regions g ON g.region_id = r.region_id
      WHERE r.date_precision = '#{GamedbRelease.date_precisions[:day]}'
    SQL
    RANKED_RELEASES_WINDOW_SQL = <<~SQL.squish
      WINDOW canonical_order AS (
        PARTITION BY r.game_id
        ORDER BY (g.region_code = '#{JAPAN_REGION_CODE}') ASC, r.release_date ASC, r.release_id ASC
      )
    SQL

    # The canonical Release of every game, for the due feed's
    # `release_id IN (...)` filter.
    CANONICAL_RELEASE_IDS_SQL = <<~SQL.squish
      SELECT ranked.release_id
      FROM (#{RANKED_RELEASES_SELECT_SQL} #{RANKED_RELEASES_WINDOW_SQL}) ranked
      WHERE ranked.canonical_rank = 1
    SQL

    # Row counts written by each step.
    Result = Data.define(:upserted, :restored, :skipped)

    def self.call(game_id)
      new(game_id).call
    end

    def initialize(game_id)
      @game_id = Integer(game_id)
    end

    def call
      Result.new(upserted: upsert_announcements, restored: restore_non_canonical, skipped: mark_non_canonical)
    end

    private

    # Step 1. On conflict (release_id PK) only a pending row whose time
    # actually changed is moved: rows the send loop already owns
    # (`sent_at`/`skipped_at` set) are never touched. `announce_at` is UTC
    # midnight LEAD days before the Release's date.
    def upsert_announcements
      exec_update(<<~SQL.squish)
        INSERT INTO gamedb_release_announcements
          (release_id, announce_at, sent_at, skipped_at, skip_reason, created_at, updated_at)
        SELECT r.release_id, r.release_date - INTERVAL '#{LEAD.in_days.to_i} days', NULL, NULL, NULL,
               CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM gamedb_releases r
         WHERE r.date_precision = #{quote(GamedbRelease.date_precisions[:day])}
           AND r.game_id = #{@game_id}
        ON CONFLICT (release_id) DO UPDATE SET
          announce_at = EXCLUDED.announce_at,
          updated_at = CURRENT_TIMESTAMP
        WHERE gamedb_release_announcements.sent_at IS NULL
          AND gamedb_release_announcements.skipped_at IS NULL
          AND gamedb_release_announcements.announce_at <> EXCLUDED.announce_at
      SQL
    end

    # Step 2. The `release_id IN (...this game...)` guard is required: the
    # `NOT EXISTS` is over this game's ranked Releases only, so without it a
    # different game's skip would falsely qualify for restore.
    def restore_non_canonical
      exec_update(<<~SQL.squish)
        UPDATE gamedb_release_announcements
           SET skipped_at = NULL,
               skip_reason = NULL,
               updated_at = CURRENT_TIMESTAMP
         WHERE sent_at IS NULL
           AND skip_reason IN (#{quote(PORT_ONLY_RELEASE_REASON)}, #{quote(SAME_DAY_DUPLICATE_REASON)})
           AND release_id IN (SELECT release_id FROM gamedb_releases WHERE game_id = #{@game_id})
           AND NOT EXISTS (
             SELECT 1
             FROM (#{ranked_releases_sql}) ranked
             WHERE ranked.canonical_rank > 1
               AND ranked.release_id = gamedb_release_announcements.release_id
           )
      SQL
    end

    # Step 3. `same-day-platform-duplicate` for a Release on the canonical
    # Release's date (any platform or region), `port-only-release` for any
    # other date, including a Japanese Release earlier than a canonical one
    # outside Japan. `src` is the game's ranked non-canonical Releases, so the
    # join self-scopes to this game; only pending rows are touched.
    def mark_non_canonical
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
            FROM (#{ranked_releases_sql}) ranked
            WHERE ranked.canonical_rank > 1
          ) src
         WHERE a.release_id = src.release_id
           AND a.sent_at IS NULL
           AND a.skipped_at IS NULL
      SQL
    end

    # The game's Releases ranked for canonicality. The window partitions by
    # `game_id`, so narrowing the rows to one game yields the same ranks as
    # the due feed's global query.
    def ranked_releases_sql
      "#{RANKED_RELEASES_SELECT_SQL} AND r.game_id = #{@game_id} #{RANKED_RELEASES_WINDOW_SQL}"
    end

    def exec_update(sql)
      GamedbReleaseAnnouncement.connection.exec_update(sql)
    end

    def quote(value)
      GamedbReleaseAnnouncement.connection.quote(value)
    end
  end
end

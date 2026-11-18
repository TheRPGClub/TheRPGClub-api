# frozen_string_literal: true

module Gamedb
  # The weekly IGDB refresh (api#393, ADR 0009): refreshes the Releases of every
  # GameDB game that still has an upcoming, imprecise or missing date through
  # the same in-place sync as POST /games/:id/refresh-releases, so a delayed
  # game moves on the Release Calendar, and in its announcement, without anyone
  # pressing "Refresh release info".
  class ReleaseRefreshJob < ApplicationJob
    queue_as :default

    # Gap between games to stay within IGDB's rate limit, as the image backfill.
    class_attribute :pause_seconds, default: 0.25

    # Returns the ids of the games it refreshed (or tried to: failures are
    # logged), for the one-off `gamedb:refresh_releases` run.
    def perform
      importer = IgdbGameImporter.new
      game_ids.each_with_index do |game_id, index|
        sleep(pause_seconds) if index.positive? && pause_seconds.positive?
        refresh(importer, game_id)
      end
    end

    private

    # One game failing (IGDB error, game gone from IGDB, a bad row) is logged
    # and skipped. Missing IGDB credentials stop the run instead, since every
    # game would fail the same way.
    def refresh(importer, game_id)
      importer.refresh_releases!(game_id)
    rescue Igdb::Client::ConfigurationError
      raise
    rescue StandardError => error
      Rails.logger.error("[Gamedb::ReleaseRefreshJob] Game #{game_id}: #{error.class}: #{error.message}")
    end

    # A Release is still due while its period has not ended: an exact day
    # through that day, a month, quarter or year through its last day.
    PERIOD_NOT_ENDED_SQL = "#{GamedbRelease.period_ends_on_sql('gamedb_releases')} >= :today".freeze

    # Every game with an IGDB id that has a Release dated today or later, a
    # vague Release whose period has not ended, a TBA Release, or no Releases
    # at all and no past first-release date. "Today" is the UTC calendar day,
    # as in the release-announcement due feed.
    def game_ids
      today = Time.now.utc.to_date
      releases = GamedbRelease.where("gamedb_releases.game_id = gamedb_games.game_id")
      due = releases.where(date_precision: "tba").or(releases.where(PERIOD_NOT_ENDED_SQL, today: today))
      undated = GamedbGame.where.not(releases.arel.exists)
        .where("gamedb_games.initial_release_date IS NULL OR gamedb_games.initial_release_date::date >= ?", today)

      GamedbGame.where.not(igdb_id: nil)
        .merge(GamedbGame.where(due.arel.exists).or(undated))
        .order(:game_id)
        .pluck(:game_id)
    end
  end
end

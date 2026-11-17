# frozen_string_literal: true

module Gamedb
  # The in-place IGDB refresh of one game's Releases (ADR 0009). Game import,
  # POST /games/:id/refresh-releases and anything else that syncs Releases from
  # IGDB hand it the Releases IGDB reports, and it matches each one on game +
  # platform + region:
  #
  # - an existing IGDB Release takes IGDB's date and Date Precision;
  # - otherwise the oldest matching Manual Release is adopted: it becomes an
  #   IGDB Release and takes IGDB's date and Date Precision (any other matches
  #   stay Manual);
  # - otherwise a new IGDB Release is inserted.
  #
  # IGDB Releases IGDB no longer reports are removed with their announcement;
  # when that announcement was sent, the game keeps `release_announced_at` so
  # it is never announced again. Manual Releases are never updated or removed.
  #
  # Because a Release keeps its id, its announcement keeps its delivery state:
  # a pending announcement follows a moved date (`announce_at` = date - 7 days),
  # an unsent one is dropped when its Release stops being an exact day, and a
  # sent or skipped one is never reset, so a refresh inside the 7-day
  # window can no longer make the due feed offer the game again.
  #
  # Choosing which IGDB dates to report (and touching the game for the
  # relations cache) is the caller's job.
  class ReleaseSync
    # The release announcement goes out this long before the Release's date
    # (matches ReleaseAnnouncementsController#upsert_announcements).
    ANNOUNCEMENT_LEAD = 7.days

    # One Release as IGDB reports it, already resolved to local ids, with its
    # plain date at its Date Precision (no date for `tba`).
    Reported = Data.define(:platform_id, :region_id, :release_date, :date_precision) do
      def key = [ platform_id, region_id ]
    end

    def self.call(game, reported)
      new(game).call(reported)
    end

    def initialize(game)
      @game = game
    end

    def call(reported)
      GamedbRelease.transaction do
        # Serialise refreshes of the same game (the pressed refresh and the
        # weekly job) so two runs cannot both insert the same IGDB Release.
        @game.lock!
        releases = GamedbRelease.where(game_id: @game.game_id).includes(:announcement).order(:release_id).to_a
        candidates = releases.group_by { |release| [ release.platform_id, release.region_id ] }

        kept = reported.uniq(&:key).map { |release| apply!(release, candidates.fetch(release.key, [])) }
        remove!(releases.select(&:source_igdb?) - kept)
      end
      @game.releases.reset
    end

    private

    # Releases are ordered by id, so `find` picks the existing IGDB Release
    # first, then the oldest Manual Release.
    def apply!(reported, matches)
      release = matches.find(&:source_igdb?) || matches.find(&:source_manual?)
      return insert!(reported) if release.nil?

      release.source = "igdb"
      release.release_date = reported.release_date
      release.date_precision = reported.date_precision
      release.save!
      follow_date!(release) if release.saved_change_to_release_date? || release.saved_change_to_date_precision?
      release
    end

    def insert!(reported)
      GamedbRelease.create!(
        game_id: @game.game_id,
        platform_id: reported.platform_id,
        region_id: reported.region_id,
        format: nil,
        release_date: reported.release_date,
        date_precision: reported.date_precision,
        source: "igdb"
      )
    end

    # Only `day` Releases are announced, so a Release that turned vague or
    # TBA loses its unsent announcement (pending or skipped; a later exact day
    # schedules a fresh one). Otherwise only a pending announcement moves with
    # its date; the send loop owns sent/skipped rows.
    def follow_date!(release)
      announcement = release.announcement
      return if announcement.nil? || announcement.sent_at
      return announcement.destroy! unless release.date_precision_day?
      return if announcement.skipped_at

      announcement.update!(announce_at: release.release_date - ANNOUNCEMENT_LEAD)
    end

    # The announcement row FKs to the Release, so it goes too, whatever its
    # state: a removed Release has nothing left to announce. A sent one is the
    # game's announcement, so the game keeps when it went out
    # (`release_announced_at`) and the due feed never announces it again.
    def remove!(releases)
      return if releases.empty?

      keep_announced_at!(releases.filter_map { |release| release.announcement&.sent_at }.min)
      release_ids = releases.map(&:release_id)
      GamedbReleaseAnnouncement.where(release_id: release_ids).delete_all
      GamedbRelease.where(release_id: release_ids).delete_all
    end

    def keep_announced_at!(sent_at)
      return if sent_at.nil? || @game.release_announced_at

      @game.update_columns(release_announced_at: sent_at)
    end
  end
end

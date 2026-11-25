# frozen_string_literal: true

module Api
  module V1
    # Manual Release writes for a game (gamedb_releases): create (the bot's
    # `addReleaseInfo`), edit and delete (the Game Edit page). Reads live on
    # GamesController#releases. All admin/service-only. IGDB Releases are owned
    # by the IGDB refresh, so edit and delete refuse them.
    class ReleasesController < ApplicationController
      feature :game_index

      WRITABLE_FIELDS = %w[platform_id region_id format release_date date_precision notes].freeze

      before_action :require_admin_or_service!
      before_action :load_manual_release, only: %i[update destroy]

      # POST /api/v1/games/:id/releases
      #   { data: { platform_id, region_id, format, release_date, date_precision, notes } }
      #
      # Adds a release for the game. `platform_id` and `region_id` are required
      # (the belongs_to presence validations reject a missing or unknown id with
      # a 422); `format` must be `Physical`, `Digital` or null; `release_date` and
      # `notes` are optional. `date_precision` (day, month, quarter, year, tba)
      # is optional: omitted or null, it is `day`, or `tba` without a date. A
      # TBA Release has no date and every other one has one, a vague date on the
      # first day of its period; anything else is a 422. A plain insert —
      # duplicates are allowed, matching the bot. Always a Manual Release
      # (`source` is not writable), so no IGDB refresh ever changes or removes
      # it. Returns the created release (platform/region labels flattened in).
      def create
        game = GamedbGame.find(params[:id])
        release = GamedbRelease.transaction do
          # Locked as an edit and Gamedb::ReleaseSync lock it, so the schedule
          # is rebuilt from a settled set of Releases.
          game.lock!
          created = GamedbRelease.source_manual.create!(release_data.merge(game_id: game.game_id))
          # Schedule its announcement now, as an edit or IGDB refresh does,
          # rather than waiting for a sweep.
          Gamedb::ReleaseAnnouncementSchedule.call(game.game_id)
          # Bump the game's updated_at so GamesController#relations_data's cache
          # (keyed on it) picks up the new release -- the release lives on a
          # child table, so nothing else here saves the game record.
          game.touch
          created
        end

        render json: { data: release_json(release) }, status: :created
      end

      # PATCH /api/v1/releases/:id
      #   { data: { platform_id?, region_id?, format?, release_date?, date_precision?, notes? } }
      #
      # Edits a Manual Release; only the fields sent change, with the same
      # validation as create. Clearing the date without a Date Precision makes
      # the Release TBA; dating a TBA Release without one makes it an exact day,
      # and so does dating a vague Release on a day that isn't the first of its
      # period (the first day of another period keeps it vague). A date that
      # doesn't parse is a 422. The game's release-announcement schedule is
      # rebuilt from the edit. 422 `igdb_release` for an IGDB Release.
      def update
        with_locked_manual_release do |game|
          announcement = locked_announcement
          was_offered = offered_by_due_feed?(announcement)
          @release.update!(release_data)
          unless @release.date_precision_day? || announcement&.sent_at
            drop_announcement!(game, announcement, was_offered)
          end
          Gamedb::ReleaseAnnouncementSchedule.call(game.game_id)
          game.touch
        end
      end

      # DELETE /api/v1/releases/:id
      #
      # Deletes a Manual Release with its announcement row. A sent announcement
      # still leaves the game's `release_announced_at`, so the due feed never
      # announces the game again; so does one the due feed is offering right
      # now (see #drop_announcement!). 422 `igdb_release` for an IGDB Release.
      def destroy
        with_locked_manual_release do |game|
          announcement = locked_announcement
          drop_announcement!(game, announcement, offered_by_due_feed?(announcement))
          @release.destroy!
          Gamedb::ReleaseAnnouncementSchedule.call(game.game_id)
          game.touch
        end
      end

      private

      def load_manual_release
        @release = GamedbRelease.find(params[:id])
        render_igdb_release unless @release.source_manual?
      end

      # Runs the write with the game locked, as Gamedb::ReleaseSync locks it
      # before adopting a Manual Release, then re-checks the Release: a refresh
      # that adopted it between the load and the lock made it an IGDB Release,
      # which this refuses instead of overwriting. Renders the edited Release,
      # or 204 once it is deleted.
      def with_locked_manual_release
        written = GamedbRelease.transaction do
          game = @release.game
          game.lock!
          @release.lock!
          next false unless @release.source_manual?

          yield game
          true
        end
        return render_igdb_release unless written
        return head(:no_content) if @release.destroyed?

        render json: { data: release_json(@release) }
      end

      def render_igdb_release
        render json: { error: "igdb_release", message: "An IGDB Release is kept in step by the IGDB refresh " \
                                                       "and can't be edited or deleted" },
          status: :unprocessable_content
      end

      # The Release's announcement row, locked so the bot's PATCH marking it
      # sent waits for this write (or this write sees it sent).
      def locked_announcement
        GamedbReleaseAnnouncement.lock.find_by(release_id: @release.release_id)
      end

      # Whether the due feed (ReleaseAnnouncementsController#due) can be
      # offering the announcement right now: pending, its time reached and its
      # Release still upcoming, so the bot may already be posting it.
      def offered_by_due_feed?(announcement, now = Time.current)
        return false if announcement.nil? || announcement.sent_at || announcement.skipped_at
        return false if @release.release_date.nil?

        announcement.announce_at <= now && @release.release_date > now.utc.to_date
      end

      # Removes the announcement row. The game keeps when a sent one went out,
      # so the due feed never announces it again. A row the due feed was
      # offering counts as sent now: the bot may be posting it, and its PATCH
      # marking it sent would find no row, so another Release of the game could
      # be announced too. A missed announcement is the safer failure than a
      # double one; refusing the write instead would leave staff unable to fix
      # a wrong Release during its announce week.
      def drop_announcement!(game, announcement, was_offered)
        return if announcement.nil?

        announced_at = announcement.sent_at || (Time.current if was_offered)
        game.update_columns(release_announced_at: announced_at) if announced_at && game.release_announced_at.nil?
        announcement.destroy!
      end

      # A null `date_precision` means "not stated", like an omitted one.
      def release_data
        data = request_data.slice(*WRITABLE_FIELDS)
        data.delete("date_precision") if data.key?("date_precision") && data["date_precision"].nil?
        data
      end

      # The release with the platform/region labels ReleaseResource flattens.
      def release_json(release)
        record = GamedbRelease.includes(:platform, :region).find(release.release_id)
        ReleaseResource.new(record).serializable_hash
      end
    end
  end
end

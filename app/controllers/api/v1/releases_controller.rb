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
        release = GamedbRelease.source_manual.create!(release_data.merge(game_id: game.game_id))
        # Bump the game's updated_at so GamesController#relations_data's cache
        # (keyed on it) picks up the new release -- the release lives on a
        # child table, so nothing else here saves the game record.
        game.touch

        render json: { data: release_json(release) }, status: :created
      end

      # PATCH /api/v1/releases/:id
      #   { data: { platform_id?, region_id?, format?, release_date?, date_precision?, notes? } }
      #
      # Edits a Manual Release; only the fields sent change, with the same
      # validation as create. Clearing the date without a Date Precision makes
      # the Release TBA; dating a TBA Release without one makes it an exact day.
      # The game's release-announcement schedule is rebuilt from the edit.
      # 422 `igdb_release` for an IGDB Release.
      def update
        GamedbRelease.transaction do
          @release.update!(release_data)
          @release.drop_unsent_announcement! unless @release.date_precision_day?
          Gamedb::ReleaseAnnouncementSchedule.call(@release.game_id)
          @release.game.touch
        end

        render json: { data: release_json(@release) }
      end

      # DELETE /api/v1/releases/:id
      #
      # Deletes a Manual Release with its announcement row. A sent announcement
      # still leaves the game's `release_announced_at`, so the due feed never
      # announces the game again. 422 `igdb_release` for an IGDB Release.
      def destroy
        game = @release.game
        GamedbRelease.transaction do
          sent_at = @release.announcement&.sent_at
          game.update_columns(release_announced_at: sent_at) if sent_at && game.release_announced_at.nil?
          @release.announcement&.destroy!
          @release.destroy!
          Gamedb::ReleaseAnnouncementSchedule.call(game.game_id)
          game.touch
        end

        head :no_content
      end

      private

      def load_manual_release
        @release = GamedbRelease.find(params[:id])
        return if @release.source_manual?

        render json: { error: "igdb_release", message: "An IGDB Release is kept in step by the IGDB refresh " \
                                                       "and can't be edited or deleted" },
          status: :unprocessable_content
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

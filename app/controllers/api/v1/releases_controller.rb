# frozen_string_literal: true

module Api
  module V1
    # Manual release rows for a game (gamedb_releases), the bot's
    # `addReleaseInfo`. Reads live on GamesController#releases; this is the
    # admin/service-only write.
    class ReleasesController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create]

      # POST /api/v1/games/:id/releases
      #   { data: { platform_id, region_id, format, release_date, notes } }
      #
      # Adds a release for the game. `platform_id` and `region_id` are required
      # (the belongs_to presence validations reject a missing or unknown id with
      # a 422); `format` must be `Physical`, `Digital` or null; `release_date` and
      # `notes` are optional. A plain insert — duplicates are allowed, matching
      # the bot. Returns the created release (platform/region labels flattened in).
      def create
        game = GamedbGame.find(params[:id])
        release = GamedbRelease.create!(release_data.merge(game_id: game.game_id))
        # Reload with the associations ReleaseResource flattens (platform/region).
        record = GamedbRelease.includes(:platform, :region).find(release.release_id)

        render json: { data: ReleaseResource.new(record).serializable_hash }, status: :created
      end

      private

      def release_data
        request_data.slice("platform_id", "region_id", "format", "release_date", "notes")
      end
    end
  end
end

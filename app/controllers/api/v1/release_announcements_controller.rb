# frozen_string_literal: true

module Api
  module V1
    # Scheduled release announcements (bot parity, #43). Each row is the bot's
    # plan to announce a single GamedbRelease at `announce_at`; the row is keyed
    # by `release_id` (1:1 with the release), so the member `:id` is a release_id.
    #
    # The bot's send loop owns the delivery columns (`sent_at`, `skipped_at`,
    # `skip_reason`), so they're read-only on create/update — stripped via
    # #writable_data — and the only sanctioned way to set the skip columns is the
    # dedicated #skip action. Reads are open to any authenticated caller (the bot
    # polls them); writes are admin/service-gated.
    class ReleaseAnnouncementsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create update destroy skip]

      # GET /api/v1/games/:id/release_announcements
      def game_index
        scope = GamedbReleaseAnnouncement
          .joins(:release)
          .where(gamedb_releases: { game_id: params[:id] })
        render_collection(scope, resource: ReleaseAnnouncementResource, default_order: { announce_at: :asc, release_id: :asc })
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
        record = GamedbReleaseAnnouncement.create!(writable_data)
        record.reload
        render json: { data: ReleaseAnnouncementResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/release_announcements/:id
      #
      # Reschedules a pending announcement by moving `announce_at`.
      def update
        record = GamedbReleaseAnnouncement.find(params[:id])
        record.update!(writable_data)
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

      private

      # The bot's send loop owns the delivery columns, so strip them from any
      # create/update write. `sent_at` stays bot-only; the skip columns are set
      # only via #skip (#43).
      def writable_data
        request_data.except("sent_at", "skipped_at", "skip_reason")
      end

      # Optional reason supplied with a skip; `nil` when none was sent.
      def skip_reason
        params.dig(:data, :skip_reason).presence
      end
    end
  end
end

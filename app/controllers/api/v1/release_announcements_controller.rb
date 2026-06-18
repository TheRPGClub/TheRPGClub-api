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
      before_action :require_admin_or_service!, only: %i[create update destroy skip sync]

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

      # PATCH /api/v1/games/:id/release_announcements/sync
      #
      # Admin/service-only bulk upsert of the game's announcement schedule (the
      # bot's `syncReleaseAnnouncements`). The body carries the computed pairs:
      #   { data: [ { release_id, announce_at }, ... ] }
      # Each pair is upserted by `release_id`: a new schedule row is created, an
      # existing one is moved only when `announce_at` actually changes. Rows the
      # bot's send loop already owns — `sent_at` or `skipped_at` set — are never
      # touched. Pairs without an `announce_at`, or whose `release_id` doesn't
      # belong to the path game, are ignored. Returns how many rows were written
      # (`synced`) vs left as-is (`skipped`).
      def sync
        own_release_ids = GamedbRelease.where(game_id: params[:id]).pluck(:release_id).to_set
        synced = 0
        skipped = 0

        GamedbReleaseAnnouncement.transaction do
          announcement_pairs.each do |pair|
            release_id = pair[:release_id].to_i
            announce_at = pair[:announce_at]
            if announce_at.blank? || !own_release_ids.include?(release_id)
              skipped += 1
              next
            end

            announcement = GamedbReleaseAnnouncement.find_or_initialize_by(release_id: release_id)
            if announcement.persisted? && (announcement.sent_at.present? || announcement.skipped_at.present?)
              skipped += 1
              next
            end

            announcement.announce_at = announce_at
            if announcement.changed?
              announcement.save!
              synced += 1
            else
              skipped += 1
            end
          end
        end

        render json: { data: { synced: synced, skipped: skipped } }
      end

      private

      # The bot's send loop owns the delivery columns, so strip them from any
      # create/update write. `sent_at` stays bot-only; the skip columns are set
      # only via #skip (#43).
      def writable_data
        request_data.except("sent_at", "skipped_at", "skip_reason")
      end

      # Normalize the #sync body into `[{ release_id:, announce_at: }, …]`. The
      # pairs arrive as an array under `data` (`{ data: [ {…}, {…} ] }`), or
      # nested under `data.announcements`; each entry is read by key (no
      # mass-assignment), so unknown keys are simply dropped.
      def announcement_pairs
        raw = params[:data]
        raw = raw[:announcements] if raw.is_a?(ActionController::Parameters)
        Array(raw).filter_map do |entry|
          hash = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
          next unless hash.is_a?(Hash)

          { release_id: hash[:release_id] || hash["release_id"], announce_at: hash[:announce_at] || hash["announce_at"] }
        end
      end

      # Optional reason supplied with a skip; `nil` when none was sent.
      def skip_reason
        params.dig(:data, :skip_reason).presence
      end
    end
  end
end

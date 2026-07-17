# frozen_string_literal: true

module Api
  module V1
    # Steam collection import job persistence (#166), backing the Discord
    # bot's `/collection steam-import` command as it migrates off direct SQL
    # (steamCollectionImport.sql.ts) onto the API. A Steam library is
    # processed one app at a time via the paired
    # SteamCollectionImportItemsController#next_pending poll, so the job can
    # be resumed across bot restarts. Owner-only (the bot service token
    # counts as the owner, per `require_owner!`) — this is private per-user
    # working data.
    class SteamCollectionImportsController < ApplicationController
      include TestModeRollback

      before_action :require_owner!, only: %i[create active show update]

      # POST /api/v1/steam_collection_imports
      # Body: { "data": { user_id, steam_id64, steam_profile_ref, source_profile_name, test_mode } }
      #
      # Creates the import job. `test_mode: true` marks this a dry-run
      # session — the session row itself is always persisted, but all
      # subsequent writes scoped to it are rolled back (see TestModeRollback).
      def create
        data = request_data
        record = RpgClubSteamCollectionImport.create!(
          user_id: data["user_id"],
          status: "active",
          current_index: 0,
          total_count: 0,
          steam_id64: data["steam_id64"],
          steam_profile_ref: data["steam_profile_ref"],
          source_profile_name: data["source_profile_name"],
          test_mode: ActiveModel::Type::Boolean.new.cast(data["test_mode"])
        )

        render json: { data: SteamCollectionImportResource.new(record).serializable_hash }, status: :created
      end

      # GET /api/v1/users/:user_id/steam_collection_imports/active
      #
      # The user's active or paused import, if any, for resuming after a bot
      # restart.
      def active
        record = RpgClubSteamCollectionImport
          .where(user_id: params[:user_id], status: %w[active paused])
          .order(created_at: :desc)
          .first!

        render json: { data: SteamCollectionImportResource.new(record).serializable_hash }
      end

      # GET /api/v1/steam_collection_imports/:id
      def show
        record = RpgClubSteamCollectionImport.find(params[:id])
        render json: { data: SteamCollectionImportResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/steam_collection_imports/:id
      # Body: { "data": { status, current_index } }
      def update
        record = RpgClubSteamCollectionImport.find(params[:id])
        with_test_mode_rollback(record.test_mode) { record.update!(request_data) }
        render json: { data: SteamCollectionImportResource.new(record).serializable_hash }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return request_data["user_id"] if action_name == "create"
        return nil unless params[:id].present?

        RpgClubSteamCollectionImport.find_by(import_id: params[:id])&.user_id
      end
    end
  end
end

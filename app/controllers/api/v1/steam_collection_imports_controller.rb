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

      before_action :require_owner!, only: %i[create active show update advance]

      # Steam::Client error codes that are the member's to fix (422); the
      # others are upstream failures.
      STEAM_CLIENT_ERRORS = %w[invalid_identifier private_profile].freeze
      STEAM_UPSTREAM_STATUS = { "api_rate_limited" => :service_unavailable }.freeze

      # POST /api/v1/steam_collection_imports
      # Body: { "data": { user_id, steam_id64, steam_profile_ref, source_profile_name, test_mode } }
      #
      # POST /api/v1/users/:user_id/steam_collection_imports
      # Body: { "data": { steam_profile, test_mode } }
      #
      # Creates the import job. The body-owner form (the bot) creates an empty
      # session and inserts items via POST .../:id/items. The user-nested form
      # (the web, #289) resolves `steam_profile` and fetches the library via
      # Steam::Client, then creates the session and its items in one go.
      # `test_mode: true` marks a dry-run session — the session row itself is
      # always persisted, but all subsequent writes scoped to it (including
      # the user-nested form's items) are rolled back (see TestModeRollback).
      def create
        params[:user_id].present? ? create_from_steam_profile : create_session
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
      UPDATE_ATTRS = %w[status current_index].freeze

      def update
        record = RpgClubSteamCollectionImport.find(params[:id])
        with_test_mode_rollback(record.test_mode) { record.update!(request_data.slice(*UPDATE_ATTRS)) }
        render json: { data: SteamCollectionImportResource.new(record).serializable_hash }
      end

      # POST /api/v1/steam_collection_imports/:id/advance
      #
      # Server-side workflow step (#289, see Imports::SteamWorkflow#advance):
      # auto-applies single exact matches (at most AUTO_APPLY_CAP per call)
      # and returns the next item that needs a human with its candidates, or
      # a null item once the import is completed (or the cap was hit while the
      # import is still active: advance again). 422 import_not_active unless
      # the import is active. Rolled back for a test_mode import.
      def advance
        import = RpgClubSteamCollectionImport.find(params[:id])
        return render_import_not_active unless import.status == "active"

        payload = with_test_mode_rollback(import.test_mode) do
          import.lock!
          workflow = Imports::SteamWorkflow.new(import)
          review_payload(import, workflow.advance, workflow.counts)
        end

        render json: { data: payload }
      end

      private

      def create_session
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

      def create_from_steam_profile
        data = request_data
        user_id = params[:user_id]
        if RpgClubSteamCollectionImport.open_for_user(user_id).exists?
          return render json: { error: OneOpenImportPerUser::ERROR_MESSAGE }, status: :unprocessable_entity
        end

        client = Steam::Client.new
        profile = client.resolve_profile(data["steam_profile"])
        library = client.owned_games(profile[:steam_id64])

        record = RpgClubSteamCollectionImport.create!(
          user_id: user_id, status: "active", current_index: 0, total_count: 0,
          steam_id64: library[:steam_id64], steam_profile_ref: profile[:raw_identifier].to_s.strip,
          source_profile_name: library[:profile_name],
          test_mode: ActiveModel::Type::Boolean.new.cast(data["test_mode"]) || false
        )
        with_test_mode_rollback(record.test_mode) do
          rows = Imports::SteamWorkflow.item_rows(record.import_id, library[:games])
          RpgClubSteamCollectionImportItem.insert_all(rows) if rows.any?
          record.update!(total_count: rows.size)
        end

        render json: { data: SteamCollectionImportResource.new(record).serializable_hash }, status: :created
      rescue Steam::Client::ConfigurationError => error
        render json: { error: "steam_not_configured", message: error.message }, status: :service_unavailable
      rescue Steam::Client::Error => error
        render json: { error: error.code, message: error.message }, status: steam_error_status(error.code)
      end

      def render_import_not_active
        render json: { error: "import_not_active", message: "This import is not active." },
          status: :unprocessable_entity
      end

      def review_payload(import, review, counts)
        {
          import: SteamCollectionImportResource.new(import).serializable_hash,
          item: review.item && SteamCollectionImportItemResource.new(review.item).serializable_hash,
          candidates: Imports::CandidatePresenter.as_json(review.candidates),
          match_confidence: review.match_confidence,
          auto_applied: review.auto_applied,
          counts: counts
        }
      end

      def steam_error_status(code)
        return :unprocessable_entity if STEAM_CLIENT_ERRORS.include?(code)

        STEAM_UPSTREAM_STATUS.fetch(code, :bad_gateway)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return request_data["user_id"] if action_name == "create"
        return nil unless params[:id].present?

        RpgClubSteamCollectionImport.find_by(import_id: params[:id])&.user_id
      end
    end
  end
end

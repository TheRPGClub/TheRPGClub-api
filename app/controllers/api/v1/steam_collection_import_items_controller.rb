# frozen_string_literal: true

module Api
  module V1
    # Per-app items of a RpgClubSteamCollectionImport (#166): the raw Steam
    # app/playtime fields plus the resolved match and outcome once the bot's
    # matcher has run an app. Owner-only, resolved through the parent import.
    class SteamCollectionImportItemsController < ApplicationController
      include TestModeRollback

      before_action :require_owner!, only: %i[create next_pending counts show update]

      # POST /api/v1/steam_collection_imports/:id/items
      # Body: { "data": { items: [...] } }
      #
      # Bulk-inserts pending items for the import. Rolled back along with
      # the updated total_count if the import is in test_mode.
      def create
        import = RpgClubSteamCollectionImport.find(params[:id])
        items = Array(request_data["items"])

        with_test_mode_rollback(import.test_mode) do
          rows = items.each_with_index.map { |item, index| item_row(import.import_id, item, index) }
          RpgClubSteamCollectionImportItem.insert_all(rows) if rows.any?
          import.update!(total_count: import.total_count + rows.size)
        end

        render json: { data: SteamCollectionImportResource.new(import).serializable_hash }, status: :created
      end

      # GET /api/v1/steam_collection_imports/:id/items/next_pending
      #
      # The next pending item ordered by row_index, or null once every app has
      # been processed.
      def next_pending
        import = RpgClubSteamCollectionImport.find(params[:id])
        record = import.items.where(status: "pending").order(:row_index).first

        render json: { data: record && SteamCollectionImportItemResource.new(record).serializable_hash }
      end

      # GET /api/v1/steam_collection_imports/:id/items/counts
      #
      # Item counts grouped by status and by result_reason, replacing the
      # bot's countItemsByStatus/countItemsByReason.
      def counts
        import = RpgClubSteamCollectionImport.find(params[:id])

        render json: {
          data: {
            import_id: import.import_id,
            by_status: import.items.group(:status).count,
            by_result_reason: import.items.group(:result_reason).count
          }
        }
      end

      # GET /api/v1/steam_collection_import_items/:id
      def show
        record = RpgClubSteamCollectionImportItem.find(params[:id])
        render json: { data: SteamCollectionImportItemResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/steam_collection_import_items/:id
      # Body: { "data": { status, match_confidence, match_candidate_json,
      #                    gamedb_game_id, collection_entry_id, result_reason, error_text } }
      def update
        record = RpgClubSteamCollectionImportItem.find(params[:id])
        with_test_mode_rollback(record.import.test_mode) { record.update!(request_data) }
        render json: { data: SteamCollectionImportItemResource.new(record).serializable_hash }
      end

      private

      def item_row(import_id, item, index)
        {
          import_id: import_id,
          row_index: item["row_index"] || index,
          steam_app_id: item["steam_app_id"],
          steam_app_name: item["steam_app_name"],
          playtime_forever_min: item["playtime_forever_min"],
          playtime_windows_min: item["playtime_windows_min"],
          playtime_mac_min: item["playtime_mac_min"],
          playtime_linux_min: item["playtime_linux_min"],
          playtime_deck_min: item["playtime_deck_min"],
          last_played_at: item["last_played_at"],
          status: "pending"
        }
      end

      def resolve_owner_id
        case action_name
        when "create", "next_pending", "counts"
          RpgClubSteamCollectionImport.find_by(import_id: params[:id])&.user_id
        when "show", "update"
          RpgClubSteamCollectionImportItem.find_by(item_id: params[:id])&.import&.user_id
        end
      end
    end
  end
end

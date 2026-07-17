# frozen_string_literal: true

module Api
  module V1
    # Per-row items of a RpgClubCollectionCsvImport (#163): the raw parsed CSV
    # fields plus the resolved match and outcome once the bot's matcher has run
    # a row. Owner-only, resolved through the parent import.
    class CollectionCsvImportItemsController < ApplicationController
      before_action :require_owner!, only: %i[next_pending show update]

      # GET /api/v1/collection_csv_imports/:id/items/next_pending
      #
      # The next PENDING item ordered by row_index, or null once every row has
      # been processed.
      def next_pending
        import = RpgClubCollectionCsvImport.find(params[:id])
        record = import.items.where(status: "PENDING").order(:row_index).first

        render json: { data: record && CollectionCsvImportItemResource.new(record).serializable_hash }
      end

      # GET /api/v1/collection_csv_import_items/:id
      def show
        record = RpgClubCollectionCsvImportItem.find(params[:id])
        render json: { data: CollectionCsvImportItemResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/collection_csv_import_items/:id
      # Body: { "data": { status, match_confidence, match_candidate_json,
      #                    gamedb_game_id, collection_entry_id, result_reason, error_text } }
      def update
        record = RpgClubCollectionCsvImportItem.find(params[:id])
        record.update!(request_data)
        render json: { data: CollectionCsvImportItemResource.new(record).serializable_hash }
      end

      private

      def resolve_owner_id
        return RpgClubCollectionCsvImport.find_by(import_id: params[:id])&.user_id if action_name == "next_pending"
        return nil unless params[:id].present?

        RpgClubCollectionCsvImportItem.find_by(item_id: params[:id])&.import&.user_id
      end
    end
  end
end

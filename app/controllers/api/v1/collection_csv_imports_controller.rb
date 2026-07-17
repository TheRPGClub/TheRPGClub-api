# frozen_string_literal: true

module Api
  module V1
    # Collection CSV import job persistence (#163), backing the Discord bot's
    # `/collection collection-csv-import` command as it migrates off direct SQL
    # (`rpg_club_collection_csv_imports`, collectionCsvImport.sql.ts) onto the
    # API. A large CSV is processed one row at a time via the paired
    # CollectionCsvImportItemsController#next_pending poll, so the job can be
    # resumed across bot restarts. Owner-only (the bot service token counts as
    # the owner, per `require_owner!`) — this is private per-user working data.
    class CollectionCsvImportsController < ApplicationController
      before_action :require_owner!, only: %i[create active show update summary]

      # POST /api/v1/users/:user_id/collection_csv_imports
      # Body: { "data": { source_file_name, source_file_size, template_version, items: [...] } }
      #
      # Creates the import job and inserts all row items in one call. Each
      # entry in `items` becomes a pending RpgClubCollectionCsvImportItem;
      # `row_index` defaults to the entry's position in the array.
      def create
        data = request_data
        items = Array(data["items"])

        record = nil
        ActiveRecord::Base.transaction do
          record = RpgClubCollectionCsvImport.create!(
            user_id: params[:user_id],
            status: "active",
            current_index: 0,
            total_count: items.size,
            source_file_name: data["source_file_name"],
            source_file_size: data["source_file_size"],
            template_version: data["template_version"]
          )

          rows = items.each_with_index.map { |item, index| item_row(record.import_id, item, index) }
          RpgClubCollectionCsvImportItem.insert_all(rows) if rows.any?
        end

        render json: { data: CollectionCsvImportResource.new(record).serializable_hash }, status: :created
      end

      # GET /api/v1/users/:user_id/collection_csv_imports/active
      #
      # The user's active or paused import, if any, for resuming after a bot
      # restart.
      def active
        record = RpgClubCollectionCsvImport
          .where(user_id: params[:user_id], status: %w[active paused])
          .order(created_at: :desc)
          .first!

        render json: { data: CollectionCsvImportResource.new(record).serializable_hash }
      end

      # GET /api/v1/collection_csv_imports/:id
      def show
        record = RpgClubCollectionCsvImport.find(params[:id])
        render json: { data: CollectionCsvImportResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/collection_csv_imports/:id
      # Body: { "data": { status, current_index } }
      def update
        record = RpgClubCollectionCsvImport.find(params[:id])
        record.update!(request_data)
        render json: { data: CollectionCsvImportResource.new(record).serializable_hash }
      end

      # GET /api/v1/collection_csv_imports/:id/summary
      #
      # Item counts grouped by status and by result_reason, replacing the
      # bot's countItemsByStatus/countItemsByReason.
      def summary
        record = RpgClubCollectionCsvImport.find(params[:id])

        render json: {
          data: {
            import_id: record.import_id,
            by_status: record.items.group(:status).count,
            by_result_reason: record.items.group(:result_reason).count
          }
        }
      end

      private

      def item_row(import_id, item, index)
        {
          import_id: import_id,
          row_index: item["row_index"] || index,
          raw_title: item["raw_title"],
          raw_platform: item["raw_platform"],
          raw_ownership_type: item["raw_ownership_type"],
          raw_note: item["raw_note"],
          raw_gamedb_id: item["raw_gamedb_id"],
          raw_igdb_id: item["raw_igdb_id"],
          status: "pending"
        }
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        RpgClubCollectionCsvImport.find_by(import_id: params[:id])&.user_id
      end
    end
  end
end

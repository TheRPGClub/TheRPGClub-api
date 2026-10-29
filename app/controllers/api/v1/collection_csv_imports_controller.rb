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
      include TestModeRollback

      before_action :require_owner!, only: %i[create active show update summary]

      # Upper bound on an uploaded `csv_text`, so one request can't parse an
      # arbitrarily large file.
      MAX_CSV_BYTES = 2.megabytes
      TEMPLATE_VERSION = "1.0"

      # POST /api/v1/users/:user_id/collection_csv_imports
      # Body: { "data": { csv_text, source_file_name, test_mode } }   (web, #290)
      #   or  { "data": { source_file_name, source_file_size, template_version, items: [...], test_mode } }   (bot)
      #
      # Creates the import job and inserts all row items in one call. With
      # `csv_text` the file is parsed and validated here
      # (Imports::CollectionCsvParser); any problem rejects the whole file with
      # 422 `{error: "invalid_csv", errors: [{row_index, column, message}]}` and
      # nothing is created. Otherwise each entry in the pre-parsed `items`
      # becomes a pending item; `row_index` defaults to the entry's position.
      # `test_mode: true` marks this a dry-run session — the session row
      # itself is always persisted, but all subsequent writes scoped to it are
      # rolled back (see TestModeRollback).
      def create
        data = request_data
        test_mode = ActiveModel::Type::Boolean.new.cast(data["test_mode"]) || false

        if data.key?("csv_text")
          create_from_csv_text(data, test_mode)
        else
          items = Array(data["items"])
          create_import(
            { source_file_name: data["source_file_name"], source_file_size: data["source_file_size"],
              template_version: data["template_version"] },
            items.each_with_index.map { |item, index| item_row(item, index) },
            test_mode
          )
        end
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
      UPDATE_ATTRS = %w[status current_index].freeze

      def update
        record = RpgClubCollectionCsvImport.find(params[:id])
        with_test_mode_rollback(record.test_mode) { record.update!(request_data.slice(*UPDATE_ATTRS)) }
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

      def create_from_csv_text(data, test_mode)
        csv_text = data["csv_text"].to_s
        if csv_text.bytesize > MAX_CSV_BYTES
          return render_invalid_csv([ { row_index: 1, column: "file",
                                        message: "CSV file is larger than #{MAX_CSV_BYTES / 1.megabyte} MB." } ])
        end

        parsed = Imports::CollectionCsvParser.new(platform_resolver: Imports::PlatformResolver.new).parse(csv_text)
        return render_invalid_csv(parsed.errors) unless parsed.ok?

        create_import(
          { source_file_name: data["source_file_name"], source_file_size: csv_text.bytesize,
            template_version: TEMPLATE_VERSION },
          parsed.rows.map { |row| parsed_row(row) },
          test_mode
        )
      end

      def create_import(attributes, rows, test_mode)
        record = RpgClubCollectionCsvImport.create!(
          user_id: params[:user_id], status: "active", current_index: 0, total_count: rows.size,
          test_mode: test_mode, **attributes
        )

        with_test_mode_rollback(test_mode) do
          rows = rows.map { |row| row.merge(import_id: record.import_id, status: "pending") }
          RpgClubCollectionCsvImportItem.insert_all(rows) if rows.any?
        end

        render json: { data: CollectionCsvImportResource.new(record).serializable_hash }, status: :created
      end

      def render_invalid_csv(errors)
        render json: { error: "invalid_csv", errors: errors }, status: :unprocessable_content
      end

      def parsed_row(row)
        {
          row_index: row.row_index,
          raw_title: row.title,
          raw_platform: row.raw_platform,
          raw_ownership_type: row.raw_ownership_type,
          raw_note: row.raw_note,
          raw_gamedb_id: row.gamedb_id,
          raw_igdb_id: row.igdb_id,
          platform_id: row.platform_id,
          ownership_type: row.ownership_type,
          note: row.raw_note
        }
      end

      # insert_all needs every row to carry the same keys.
      def item_row(item, index)
        {
          row_index: item["row_index"] || index,
          raw_title: item["raw_title"],
          raw_platform: item["raw_platform"],
          raw_ownership_type: item["raw_ownership_type"],
          raw_note: item["raw_note"],
          raw_gamedb_id: item["raw_gamedb_id"],
          raw_igdb_id: item["raw_igdb_id"],
          platform_id: nil,
          ownership_type: nil,
          note: nil
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

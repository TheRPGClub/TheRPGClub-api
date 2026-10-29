# frozen_string_literal: true

module Api
  module V1
    # Completionator import job persistence (#164), backing the Discord bot's
    # `/game-completion import-completionator` command as it migrates off
    # direct SQL (`rpg_club_completionator_imports`, completionatorImport.sql.ts)
    # onto the API. A large export is processed one row at a time via the
    # paired CompletionatorImportItemsController#next_pending poll, so the job
    # can be resumed across bot restarts. Owner-only (the bot service token
    # counts as the owner, per `require_owner!`) — this is private per-user
    # working data.
    class CompletionatorImportsController < ApplicationController
      include TestModeRollback

      before_action :require_owner!, only: %i[create active show update summary advance]

      # POST /api/v1/users/:user_id/completionator_imports
      # Body: { "data": { source_filename, csv_text | items: [...], test_mode } }
      #
      # Creates the import job and inserts all row items in one call. With
      # `csv_text` (the web, #291) the raw Completionator export is parsed
      # server-side (Imports::CompletionatorCsvParser); a malformed or empty
      # export is a 422 `invalid_csv` and creates nothing. Otherwise (the bot)
      # each entry in `items` becomes a pending RpgClubCompletionatorImportItem;
      # `row_index` defaults to the entry's position in the array. `test_mode:
      # true` marks this a dry-run session — the session row itself is always
      # persisted, but all subsequent writes scoped to it are rolled back
      # (see TestModeRollback).
      def create
        data = request_data
        items = data["csv_text"].nil? ? Array(data["items"]) : parse_csv(data["csv_text"])
        return if performed?

        test_mode = ActiveModel::Type::Boolean.new.cast(data["test_mode"]) || false

        record = RpgClubCompletionatorImport.create!(
          user_id: params[:user_id],
          status: "active",
          current_index: 0,
          total_count: items.size,
          source_filename: data["source_filename"],
          test_mode: test_mode
        )

        with_test_mode_rollback(test_mode) do
          rows = items.each_with_index.map { |item, index| item_row(record.import_id, item, index) }
          RpgClubCompletionatorImportItem.insert_all(rows) if rows.any?
        end

        render json: { data: CompletionatorImportResource.new(record).serializable_hash }, status: :created
      end

      # GET /api/v1/users/:user_id/completionator_imports/active
      #
      # The user's active or paused import, if any, for resuming after a bot
      # restart.
      def active
        record = RpgClubCompletionatorImport
          .where(user_id: params[:user_id], status: %w[active paused])
          .order(created_at: :desc)
          .first!

        render json: { data: CompletionatorImportResource.new(record).serializable_hash }
      end

      # GET /api/v1/completionator_imports/:id
      def show
        record = RpgClubCompletionatorImport.find(params[:id])
        render json: { data: CompletionatorImportResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/completionator_imports/:id
      # Body: { "data": { status, current_index } }
      UPDATE_ATTRS = %w[status current_index].freeze

      def update
        record = RpgClubCompletionatorImport.find(params[:id])
        with_test_mode_rollback(record.test_mode) { record.update!(request_data.slice(*UPDATE_ATTRS)) }
        render json: { data: CompletionatorImportResource.new(record).serializable_hash }
      end

      # GET /api/v1/completionator_imports/:id/summary
      #
      # Item counts grouped by status, replacing the bot's
      # countItemsByStatus.
      def summary
        record = RpgClubCompletionatorImport.find(params[:id])

        render json: {
          data: {
            import_id: record.import_id,
            by_status: record.items.group(:status).count
          }
        }
      end

      # POST /api/v1/completionator_imports/:id/advance
      #
      # The server-side review loop (#291, see Imports::CompletionatorWorkflow):
      # applies automatic rows (auto-add, auto-skip) and returns the first row
      # that needs the member, as a CompletionatorReview plus the import, the
      # number of rows handled automatically, `done` and the status counts.
      # `item` is null when nothing is left (`done: true`, the import is now
      # completed) or when the per-call automatic cap was hit (`done: false`,
      # call again). Rolled back if the import is in test_mode.
      def advance
        record = RpgClubCompletionatorImport.find(params[:id])
        payload = with_test_mode_rollback(record.test_mode) do
          result = Imports::CompletionatorWorkflow.new(record).advance
          CompletionatorReviewPayload.new(result.review).as_json.merge(
            import: CompletionatorImportResource.new(result.import).serializable_hash,
            auto_processed: result.auto_processed,
            done: result.done,
            counts: record.items.group(:status).count
          )
        end

        render json: { data: payload }
      end

      private

      def parse_csv(text)
        Imports::CompletionatorCsvParser.new.parse(text).map(&:stringify_keys)
      rescue Imports::CompletionatorCsvParser::InvalidCsv => error
        render json: { error: "invalid_csv", message: error.message }, status: :unprocessable_entity
        nil
      end

      def item_row(import_id, item, index)
        {
          import_id: import_id,
          row_index: item["row_index"] || index,
          game_title: item["game_title"],
          platform_name: item["platform_name"],
          region_name: item["region_name"],
          source_type: item["source_type"],
          time_text: item["time_text"],
          completed_at: item["completed_at"],
          completion_type: item["completion_type"],
          playtime_hrs: item["playtime_hrs"],
          status: "pending"
        }
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        RpgClubCompletionatorImport.find_by(import_id: params[:id])&.user_id
      end
    end
  end
end

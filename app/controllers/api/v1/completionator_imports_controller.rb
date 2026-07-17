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
      before_action :require_owner!, only: %i[create active show update summary]

      # POST /api/v1/users/:user_id/completionator_imports
      # Body: { "data": { source_filename, items: [...] } }
      #
      # Creates the import job and inserts all row items in one call. Each
      # entry in `items` becomes a pending RpgClubCompletionatorImportItem;
      # `row_index` defaults to the entry's position in the array.
      def create
        data = request_data
        items = Array(data["items"])

        record = nil
        ActiveRecord::Base.transaction do
          record = RpgClubCompletionatorImport.create!(
            user_id: params[:user_id],
            status: "active",
            current_index: 0,
            total_count: items.size,
            source_filename: data["source_filename"]
          )

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
      def update
        record = RpgClubCompletionatorImport.find(params[:id])
        record.update!(request_data)
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

      private

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

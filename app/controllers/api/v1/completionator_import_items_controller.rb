# frozen_string_literal: true

module Api
  module V1
    # Per-row items of a RpgClubCompletionatorImport (#164): the raw parsed
    # Completionator export fields plus the resolved match and outcome once
    # the bot's matcher has run a row. Owner-only, resolved through the
    # parent import.
    class CompletionatorImportItemsController < ApplicationController
      include TestModeRollback

      before_action :require_owner!, only: %i[next_pending show update]

      # GET /api/v1/completionator_imports/:id/items/next_pending
      #
      # The next pending item ordered by row_index, or null once every row has
      # been processed.
      def next_pending
        import = RpgClubCompletionatorImport.find(params[:id])
        record = import.items.where(status: "pending").order(:row_index).first

        render json: { data: record && CompletionatorImportItemResource.new(record).serializable_hash }
      end

      # GET /api/v1/completionator_import_items/:id
      def show
        record = RpgClubCompletionatorImportItem.find(params[:id])
        render json: { data: CompletionatorImportItemResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/completionator_import_items/:id
      # Body: { "data": { status, gamedb_game_id, completion_id, error_text } }
      def update
        record = RpgClubCompletionatorImportItem.find(params[:id])
        with_test_mode_rollback(record.import.test_mode) { record.update!(request_data) }
        render json: { data: CompletionatorImportItemResource.new(record).serializable_hash }
      end

      private

      def resolve_owner_id
        return RpgClubCompletionatorImport.find_by(import_id: params[:id])&.user_id if action_name == "next_pending"
        return nil unless params[:id].present?

        RpgClubCompletionatorImportItem.find_by(item_id: params[:id])&.import&.user_id
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    # Bot-written journal message context records (#84). The bot owns all
    # writes; the API exposes full CRUD so the bot can upsert and clean up.
    class JournalMessageContextsController < ApplicationController
      # GET /api/v1/journal_message_contexts
      def index
        scope = JournalMessageContext.all
        scope = scope.where(channel_id: params[:channel_id]) if params[:channel_id].present?
        scope = scope.where(game_id: params[:game_id]) if params[:game_id].present?
        render_collection(scope, resource: JournalMessageContextResource,
          default_order: { created_at_ms: :desc })
      end

      # GET /api/v1/journal_message_contexts/:message_id
      def show
        render json: { data: JournalMessageContextResource.new(find_context).serializable_hash }
      end

      # POST /api/v1/journal_message_contexts
      def create
        record = JournalMessageContext.create!(request_data)
        render json: { data: JournalMessageContextResource.new(record).serializable_hash }, status: :created
      end

      # PATCH /PUT /api/v1/journal_message_contexts/:message_id
      def update
        record = find_context
        record.update!(request_data)
        render json: { data: JournalMessageContextResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/journal_message_contexts/:message_id
      def destroy
        find_context.destroy!
        render json: { deleted: true }
      end

      private

      def find_context
        JournalMessageContext.find_by!(message_id: params[:message_id])
      end
    end
  end
end

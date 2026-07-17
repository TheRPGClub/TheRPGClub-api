# frozen_string_literal: true

module Api
  module V1
    # Bot-written journal message context records (#84, #165). The bot owns
    # all writes, keyed on the composite (channel_id, message_id): it upserts
    # via #create, deletes a single context via #destroy, and prunes stale
    # contexts in bulk via #prune, replacing its old direct-SQL bookkeeping.
    class JournalMessageContextsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create destroy]
      before_action :require_service!, only: %i[prune]

      # GET /api/v1/journal_message_contexts
      # GET /api/v1/journal_message_contexts?created_after_ms=...
      def index
        scope = JournalMessageContext.all
        scope = scope.where(channel_id: params[:channel_id]) if params[:channel_id].present?
        scope = scope.where(game_id: params[:game_id]) if params[:game_id].present?
        scope = scope.where("created_at_ms >= ?", params[:created_after_ms]) if params[:created_after_ms].present?
        render_collection(scope, resource: JournalMessageContextResource,
          default_order: { created_at_ms: :desc })
      end

      # POST /api/v1/journal_message_contexts
      #
      # Upsert a context keyed on (channel_id, message_id), mirroring the
      # bot's upsert-on-conflict SQL call.
      def create
        data = request_data
        channel_id = data["channel_id"].presence
        message_id = data["message_id"].presence
        raise ActionController::ParameterMissing, "channel_id" if channel_id.nil?
        raise ActionController::ParameterMissing, "message_id" if message_id.nil?

        record = JournalMessageContext.find_or_initialize_by(channel_id: channel_id, message_id: message_id)
        created = record.new_record?
        record.assign_attributes(data)
        record.save!

        render json: { data: JournalMessageContextResource.new(record).serializable_hash },
          status: created ? :created : :ok
      end

      # DELETE /api/v1/journal_message_contexts/:channel_id/:message_id
      def destroy
        JournalMessageContext.find_by!(channel_id: params[:channel_id], message_id: params[:message_id]).destroy!
        render json: { deleted: true }
      end

      # DELETE /api/v1/journal_message_contexts?before_ms=<epoch ms>
      #
      # Service-only maintenance route: bulk-deletes contexts created before
      # the cutoff, replacing the bot's manual pruning call. `before_ms` is
      # required so a missing param can't wipe the whole table.
      def prune
        before_ms = params[:before_ms].presence
        return render json: { error: "before_ms is required" }, status: :bad_request if before_ms.nil?

        count = JournalMessageContext.where("created_at_ms < ?", before_ms.to_i).delete_all
        render json: { deleted: true, count: count }
      end
    end
  end
end

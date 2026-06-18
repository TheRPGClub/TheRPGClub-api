# frozen_string_literal: true

module Api
  module V1
    # Per-user presence prompt history (bot parity, #48/#110). The bot's
    # presence-detection loop owns every write — creating a prompt and later
    # marking it resolved — so writes are service-only; reads are open to any
    # authenticated caller. The user-settable opt-out preference lives in
    # PresencePromptOptsController.
    class PresencePromptsController < ApplicationController
      before_action :require_service!, only: %i[create update]

      # GET /api/v1/users/:user_id/presence_prompts
      #
      # Optional filters mirror the bot's lookups (#110): `game_title_norm`
      # (normalized title) backs getLastPromptDateForGame and countPendingForGame;
      # `status` backs the pending counts (case-insensitive — the bot may send
      # `pending`). The pagination `meta.count` is how the bot reads the counts,
      # and the newest-first order with `per=1` gives the last prompt date.
      def index
        scope = PresencePrompt.where(user_id: params[:user_id])
        scope = scope.where(game_title_norm: params[:game_title_norm]) if params[:game_title_norm].present?
        scope = scope.where(status: params[:status].to_s.upcase) if params[:status].present?
        render_collection(scope, resource: PresencePromptResource,
          default_order: { created_at: :desc, prompt_id: :desc })
      end

      # POST /api/v1/users/:user_id/presence_prompts
      #
      # createPrompt: the bot supplies the prompt identity and game titles; the
      # row starts PENDING with a DB-stamped created_at.
      def create
        record = PresencePrompt.create!(writable_create_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: PresencePromptResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/presence_prompts/:id
      #
      # markResolved: flips the lifecycle status and stamps resolved_at.
      def update
        record = PresencePrompt.find(params[:id])
        record.update!(writable_update_data)
        record.reload
        render json: { data: PresencePromptResource.new(record).serializable_hash }
      end

      private

      # On create the status starts PENDING (DB default) and resolved_at is null;
      # both belong to the resolution path, so they are not client-writable here.
      def writable_create_data
        request_data.except("status", "resolved_at", "created_at")
      end

      # Resolution touches only status + resolved_at; the prompt identity and
      # game titles are immutable once created.
      def writable_update_data
        request_data.slice("status", "resolved_at")
      end
    end
  end
end

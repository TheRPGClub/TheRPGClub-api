# frozen_string_literal: true

module Api
  module V1
    # The bot job queue (see BotJob). The service polls, claims and acks; the
    # member who caused a job, Admins and Superadmins read its status. The
    # /admin activity list shows Admins every job and other staff their own.
    class BotJobsController < ApplicationController
      before_action :require_service!, except: %i[index show]
      before_action :require_moderator_or_above!, only: :index

      DEFAULT_CLAIM = 10
      MAX_CLAIM = 50

      # GET /api/v1/bot_jobs?page=&per=, newest first. Admins, Superadmins and
      # the service see every job; Moderators only the jobs they requested.
      def index
        scope = BotJob.includes(:requested_by)
        scope = scope.where(requested_by_user_id: current_principal.id) unless admin_or_above?
        render_collection(scope, resource: BotJobResource, default_order: { id: :desc })
      end

      # POST /api/v1/bot_jobs/claim?limit=N. Answers from the machine-local
      # signal alone while no work is waiting, so the bot can poll every few
      # seconds without waking Neon.
      def claim
        limit = params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_CLAIM) : DEFAULT_CLAIM
        jobs = BotJob.poll!(limit: limit)
        render json: { data: BotJobClaimResource.new(jobs).serializable_hash }
      end

      # POST /api/v1/bot_jobs/:id/done with an optional data.result_text
      # (what the bot did, e.g. a memberscan's counts).
      def done
        acknowledge("done", result_text: params.dig(:data, :result_text).presence&.to_s)
      end

      # POST /api/v1/bot_jobs/:id/failed with data.error_message
      def failed
        error_message = params.require(:data).require(:error_message)
        acknowledge("failed", error_message: error_message.to_s)
      end

      # GET /api/v1/bot_jobs/:id
      def show
        job = BotJob.includes(:requested_by).find(params[:id])
        return unless require_requester_or_admin!(job)

        render json: { data: BotJobResource.new(job).serializable_hash }
      end

      private

      def acknowledge(status, error_message: nil, result_text: nil)
        job = BotJob.includes(:requested_by).find(params[:id])
        job.ack!(status: status, error_message: error_message, result_text: result_text)
        render json: { data: BotJobResource.new(job).serializable_hash }
      rescue BotJob::AckConflict => e
        render json: { error: e.message }, status: :conflict
      end

      def require_requester_or_admin!(job)
        requester = current_principal&.discord_user? && current_principal.id == job.requested_by_user_id
        gate_or_forbid(requester || admin_or_above?)
      end
    end
  end
end

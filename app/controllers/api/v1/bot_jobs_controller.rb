# frozen_string_literal: true

module Api
  module V1
    # The bot job queue (see BotJob). The service polls, claims and acks; the
    # member who caused a job, Admins and Superadmins read its status.
    class BotJobsController < ApplicationController
      before_action :require_service!, except: :show

      DEFAULT_CLAIM = 10
      MAX_CLAIM = 50

      # POST /api/v1/bot_jobs/claim?limit=N. Answers from the machine-local
      # signal alone while no work is waiting, so the bot can poll every few
      # seconds without waking Neon.
      def claim
        limit = params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_CLAIM) : DEFAULT_CLAIM
        jobs = BotJob.poll!(limit: limit)
        render json: { data: BotJobClaimResource.new(jobs).serializable_hash }
      end

      # POST /api/v1/bot_jobs/:id/done
      def done
        acknowledge("done")
      end

      # POST /api/v1/bot_jobs/:id/failed with data.error_message
      def failed
        error_message = params.require(:data).require(:error_message)
        acknowledge("failed", error_message: error_message.to_s)
      end

      # GET /api/v1/bot_jobs/:id
      def show
        job = BotJob.find(params[:id])
        return unless require_requester_or_admin!(job)

        render json: { data: BotJobResource.new(job).serializable_hash }
      end

      private

      def acknowledge(status, error_message: nil)
        job = BotJob.find(params[:id])
        job.ack!(status: status, error_message: error_message)
        render json: { data: BotJobResource.new(job).serializable_hash }
      rescue BotJob::AckConflict => e
        render json: { error: e.message }, status: :conflict
      end

      # TODO(api#311): swap admin_or_service? for the named admin-or-above /
      # superadmin gates once they land.
      def require_requester_or_admin!(job)
        return true if current_principal&.discord_user? && current_principal.id == job.requested_by_user_id
        return true if admin_or_service?

        render json: { error: "forbidden" }, status: :forbidden
        false
      end
    end
  end
end

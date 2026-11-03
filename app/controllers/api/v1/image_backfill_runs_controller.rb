# frozen_string_literal: true

module Api
  module V1
    # The image backfill (web parity 2, #338): a Superadmin starts a
    # Gamedb::ImageBackfillJob and reads its progress (see ImageBackfillRun).
    # Superadmin only; the service token passes too.
    class ImageBackfillRunsController < ApplicationController
      before_action :require_superadmin!

      # POST /api/v1/image_backfill_runs. 409 while a run is queued or running.
      def create
        starter_id = current_principal.discord_user? ? current_principal.id.to_s : nil
        run = ImageBackfillRun.start!(started_by_user_id: starter_id)
        render json: { data: ImageBackfillRunResource.new(run).serializable_hash }, status: :created
      rescue ImageBackfillRun::InProgress
        render json: { error: "image_backfill_in_progress", message: "An image backfill is already running" },
          status: :conflict
      end

      # GET /api/v1/image_backfill_runs/latest. 404 before the first run. A run
      # that stopped reporting progress (see ImageBackfillRun) reads as failed.
      def latest
        render_run(ImageBackfillRun.order(id: :desc).first!)
      end

      # GET /api/v1/image_backfill_runs/:id
      def show
        render_run(ImageBackfillRun.find(params[:id]))
      end

      private

      def render_run(run)
        run.reload if run.in_progress? && ImageBackfillRun.fail_stale!.positive?
        render json: { data: ImageBackfillRunResource.new(run).serializable_hash }
      end
    end
  end
end

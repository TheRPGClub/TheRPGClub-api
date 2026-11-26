# frozen_string_literal: true

module Api
  module V1
    # A Bug Report's screenshot (spec api#498, ticket api#500): its author
    # adds, replaces or removes it while the Feedback is Pending. The file is
    # kept by FeedbackScreenshots; the Feedback's `screenshot_url` serves it.
    class FeedbackScreenshotsController < ApplicationController
      feature :feedback

      before_action :find_own_feedback

      rescue_from FeedbackScreenshots::InvalidImageError do |error|
        render json: { error: "invalid_image", message: error.message }, status: :unprocessable_content
      end
      rescue_from FeedbackScreenshots::NotAllowed do |error|
        render json: { error: "screenshot_not_allowed", message: error.message }, status: :unprocessable_content
      end
      rescue_from FeedbackScreenshots::NotPending do |error|
        render json: { error: error.message }, status: :conflict
      end
      rescue_from Backblaze::Client::ConfigurationError do |error|
        render json: { error: "backblaze_not_configured", message: error.message }, status: :service_unavailable
      end
      rescue_from Backblaze::Client::RequestError do |error|
        render json: { error: "backblaze_request_failed", message: error.message }, status: :bad_gateway
      end

      # PUT /api/v1/feedback/:feedback_id/screenshot
      # Multipart: data[file] (PNG, JPEG or WebP, at most 5 MB).
      def update
        FeedbackScreenshots.new.attach!(@feedback, uploaded_file: params.dig(:data, :file))
        render_feedback
      end

      # DELETE /api/v1/feedback/:feedback_id/screenshot
      def destroy
        FeedbackScreenshots.new.remove!(@feedback)
        render_feedback
      end

      private

      # The author only (staff and the service are refused), as for withdraw.
      def find_own_feedback
        @feedback = RpgClubFeedback.find(params[:feedback_id])
        return if current_principal.discord_user? && @feedback.created_by == current_principal.id

        render json: { error: "forbidden" }, status: :forbidden
      end

      def render_feedback
        feedback = RpgClubFeedback.with_upvotes(current_principal.id).find(@feedback.feedback_id)
        render json: { data: FeedbackResource.new(feedback).serializable_hash }
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    # Suggestion review sessions (bot parity, #91). Backs the Discord bot's
    # admin review workflow (the approve/reject buttons) as it migrates
    # `SuggestionReviewSession` off direct SQL (RPGClub_GameDB#816).
    #
    # A session is keyed by `session_id` (a bot-supplied string) and tracks the
    # reviewer (`reviewer_id`), the ordered list of suggestion ids under review
    # (`suggestion_ids`, stored as a JSON string and returned verbatim), and the
    # reviewer's progress (`current_index` / `total_count`).
    #
    # Reads are open to any authenticated caller; writes are admin/service-gated.
    # Pruning expired sessions is a service-only maintenance route.
    class SuggestionReviewSessionsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create update destroy destroy_all]
      before_action :require_service!, only: %i[destroy_expired]

      # The bot expires a review session after 15 minutes of inactivity
      # (SUGGESTION_REVIEW_TTL_MS). Used as the default cutoff when #destroy_expired
      # is called without an explicit `before`.
      DEFAULT_TTL = 15.minutes

      # GET /api/v1/suggestions/review_sessions
      # GET /api/v1/suggestions/review_sessions?reviewer_id=...
      def index
        scope = RpgClubSuggestionReviewSession.all
        scope = scope.where(reviewer_id: params[:reviewer_id]) if params[:reviewer_id].present?
        render_collection(scope, resource: SuggestionReviewSessionResource, default_order: { created_at: :desc })
      end

      # GET /api/v1/suggestions/review_sessions/:id  (id is the session_id)
      def show
        record = RpgClubSuggestionReviewSession.find(params[:id])
        render json: { data: SuggestionReviewSessionResource.new(record).serializable_hash }
      end

      # POST /api/v1/suggestions/review_sessions
      def create
        record = RpgClubSuggestionReviewSession.create!(request_data)
        render json: { data: SuggestionReviewSessionResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/suggestions/review_sessions/:id
      def update
        record = RpgClubSuggestionReviewSession.find(params[:id])
        record.update!(request_data)
        render json: { data: SuggestionReviewSessionResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/suggestions/review_sessions/:id
      def destroy
        RpgClubSuggestionReviewSession.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      # DELETE /api/v1/suggestions/review_sessions?reviewer_id=...
      #
      # Deletes every session for a reviewer. `reviewer_id` is required so we
      # never wipe the whole table by accident.
      def destroy_all
        reviewer_id = params[:reviewer_id].presence
        return render json: { error: "reviewer_id is required" }, status: :bad_request if reviewer_id.nil?

        count = RpgClubSuggestionReviewSession.where(reviewer_id: reviewer_id).delete_all
        render json: { deleted: true, count: count }
      end

      # DELETE /api/v1/suggestions/review_sessions/expired?before=<iso8601>
      #
      # Service-only maintenance route: prunes sessions created before the
      # cutoff. The cutoff is the optional `before` (ISO-8601) param; when it is
      # absent or unparseable it falls back to the bot's 15-minute TTL.
      def destroy_expired
        count = RpgClubSuggestionReviewSession.where("created_at < ?", expiry_cutoff).delete_all
        render json: { deleted: true, count: count }
      end

      private

      def expiry_cutoff
        before = params[:before].presence
        before ? Time.zone.iso8601(before) : DEFAULT_TTL.ago
      rescue ArgumentError
        DEFAULT_TTL.ago
      end
    end
  end
end

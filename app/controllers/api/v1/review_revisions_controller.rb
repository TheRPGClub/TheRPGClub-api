# frozen_string_literal: true

module Api
  module V1
    # Revisions (spec api#430, ticket #433): dated returns to a Published
    # Review. Revisiting starts a Draft Revision, which autosaves through
    # `update` and goes live with `publish`; the latest Published Revision's
    # score is the Review's current score. Writes belong to the Review's
    # author (or the service), like every review write; a Draft Revision is
    # readable only by its author and Admins.
    class ReviewRevisionsController < ApplicationController
      include ReviewTakeResponses

      feature :reviews

      before_action :require_owner!, only: %i[create update destroy publish]

      # Caller-settable columns. `published_at` is set only by publishing.
      WRITABLE_ATTRS = %w[rating title body facets].freeze

      # GET /api/v1/reviews/:review_id/revisions
      #
      # The Review's Published Revisions in publish order, then its Draft
      # Revision for its author and Admins. A Draft Review reads as not found
      # for anyone else.
      def index
        review = UserGameReview.find(params[:review_id])
        drafts = reads_drafts_of?(review.user_id)
        raise ActiveRecord::RecordNotFound, "not_found" unless review.published? || drafts

        revisions = review.revision_history
        draft = review.draft_revision if drafts
        draft&.previous_rating = review.current_rating
        render json: { data: [ *revisions, *draft ].map(&:as_json) }
      end

      # POST /api/v1/reviews/:review_id/revisions
      #
      # Revisit: starts the Review's Draft Revision. Refused when the Review
      # is still a Draft (`review_not_published`) or already has a Draft
      # Revision (`draft_revision_exists`).
      def create
        review = UserGameReview.find(params[:review_id])
        record = review.revisions.new(writable_data)
        render_saved(record, record.save, status: :created)
      end

      def update
        record = UserGameReviewRevision.find(params[:id])
        record.assign_attributes(writable_data)
        render_saved(record, record.save)
      end

      # POST /api/v1/review_revisions/:id/publish
      #
      # Publishes a Draft Revision, making its score the Review's current
      # score. Refused without a score; never reversed.
      def publish
        record = UserGameReviewRevision.find(params[:id])
        render_saved(record, record.publish)
      end

      # Deleting a Published Revision restores the score before it.
      def destroy
        UserGameReviewRevision.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # Revisit may start an empty Draft Revision, so `data` may be missing.
      def writable_data
        params.fetch(:data, {}).permit!.to_h.slice(*WRITABLE_ATTRS)
      end

      def take_json(revision) = revision.as_json

      def resolve_owner_id
        if params[:review_id].present?
          UserGameReview.find_by(review_id: params[:review_id])&.user_id
        elsif params[:id].present?
          UserGameReviewRevision.joins(:review).where(revision_id: params[:id]).pick("user_game_reviews.user_id")
        end
      end
    end
  end
end

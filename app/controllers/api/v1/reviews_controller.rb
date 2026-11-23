# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      include ReviewTakeResponses

      feature :reviews

      before_action :require_owner!, only: %i[create update destroy publish]

      # Caller-settable columns. `user_id` comes from the path (or the existing
      # record) and the key is generated, so neither is accepted in the body.
      # `published_at` is set only by publishing, never by the caller.
      WRITABLE_ATTRS = %w[gamedb_game_id title body rating facets].freeze

      # GET /api/v1/users/:user_id/reviews
      #
      # A member's Published Reviews, whoever asks: their Drafts are never
      # listed here, not even for them (spec api#430).
      def index
        scope = UserGameReview.published.where(user_id: params[:user_id]).preload(:latest_revision, game: :images)
        render_collection(scope, resource: ReviewEntryResource, default_order: { created_at: :desc })
      end

      # GET /api/v1/users/:user_id/reviews/drafts
      #
      # The member's own Drafts, Draft Reviews and Draft Revisions alike,
      # newest last-touched first, with the game and its track embedded. Only the author and Admins may read it; anyone
      # else, the service included, is refused.
      def drafts
        unless reads_drafts_of?(params[:user_id])
          return render json: { error: "forbidden" }, status: :forbidden
        end

        scope = UserGameReview.takes(:drafts).where(user_id: params[:user_id]).preload(tracked_game: :images)
        render_collection(scope, resource: ReviewDraftEntryResource,
          default_order: Arel.sql("updated_at DESC, review_id DESC, revision_id DESC NULLS LAST"))
      end

      # GET /api/v1/reviews
      #
      # The Review Feed, also behind the Latest Reviews Dashboard Panel:
      # every member's Published Reviews and Published Revisions, each its own
      # entry, newest published first. Drafts are
      # never listed here, whoever asks. Members who have left the server are
      # left out. `written=1` keeps only the Reviews with text, dropping the
      # score-only quick takes.
      def recent
        scope = UserGameReview.takes(:published).with_written
          .joins(:user).where(rpg_club_users: { server_left_at: nil })
          .preload(:user, tracked_game: :images)
        scope = scope.written if ActiveModel::Type::Boolean.new.cast(params[:written])
        render_collection(scope, resource: ReviewFeedEntryResource,
          default_order: Arel.sql("published_at DESC, review_id DESC, revision_id DESC NULLS LAST"))
      end

      def game_index
        scope = UserGameReview.published.where(gamedb_game_id: params[:id]).includes(:user, :latest_revision)
        render_collection(scope, resource: ReviewUserEntryResource,
          default_order: Arel.sql("(body IS NOT NULL) DESC, created_at DESC"))
      end

      # A Draft reads as not found for anyone but its author and Admins; the
      # service principal no longer sees Drafts.
      def show
        render json: { data: take_json(readable_review) }
      end

      # `publish: true` in the body is the quick take: created and published
      # in one call, refused (`rating_required`) without a score.
      def create
        record = UserGameReview.new(writable_data.merge("user_id" => params[:user_id]))
        quick_take = ActiveModel::Type::Boolean.new.cast(request_data["publish"])
        render_saved(record, quick_take ? record.publish : record.save, status: :created)
      end

      def update
        record = UserGameReview.find(params[:id])
        record.assign_attributes(writable_data)
        render_saved(record, record.save)
      end

      # POST /api/v1/reviews/:id/publish
      #
      # Publishes a Draft. Refused without a score; never reversed. Publishing
      # a Published Review is a no-op that keeps its first publish date.
      def publish
        record = UserGameReview.find(params[:id])
        render_saved(record, record.publish)
      end

      def destroy
        UserGameReview.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def writable_data
        request_data.slice(*WRITABLE_ATTRS)
      end

      def readable_review
        review = UserGameReview.find(params[:id])
        return review if review.published? || reads_drafts_of?(review.user_id)

        raise ActiveRecord::RecordNotFound, "not_found"
      end

      # The full Review shape, with the Draft Revision for those who may read
      # it (its author and Admins), null for everyone else.
      def take_json(review)
        draft = review.draft_revision if reads_drafts_of?(review.user_id)
        draft&.previous_rating = review.current_rating
        review.as_json.merge("draft_revision" => draft&.as_json)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameReview.find_by(review_id: params[:id])&.user_id
      end
    end
  end
end

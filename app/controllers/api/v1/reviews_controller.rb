# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
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
        scope = UserGameReview.published.where(user_id: params[:user_id]).preload(game: :images)
        render_collection(scope, resource: ReviewEntryResource, default_order: { created_at: :desc })
      end

      # GET /api/v1/reviews
      #
      # The Review Feed, also behind the Latest Reviews Dashboard Panel:
      # every member's Published Reviews, newest published first. Drafts are
      # never listed here, whoever asks. Members who have left the server are
      # left out. `written=1` keeps only the Reviews with text, dropping the
      # score-only quick takes.
      def recent
        scope = UserGameReview.published.with_written
          .joins(:user).where(rpg_club_users: { server_left_at: nil })
          .preload(:user, game: :images)
        scope = scope.written if ActiveModel::Type::Boolean.new.cast(params[:written])
        render_collection(scope, resource: ReviewFeedEntryResource,
          default_order: { published_at: :desc, review_id: :desc },
          prepare: ->(page) { GameTrackSummaryResource.params_for(page.map(&:gamedb_game_id)) })
      end

      def game_index
        scope = UserGameReview.published.where(gamedb_game_id: params[:id]).includes(:user)
        render_collection(scope, resource: ReviewUserEntryResource,
          default_order: Arel.sql("(body IS NOT NULL) DESC, created_at DESC"))
      end

      # A Draft reads as not found for anyone but its author and Admins; the
      # service principal no longer sees Drafts.
      def show
        render json: { data: readable_review.as_json }
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

      # Renders the saved review, or the refusal: 422 `rating_required` when
      # a Published Review would have no score, otherwise the usual
      # validation message.
      def render_saved(record, saved, status: :ok)
        if saved
          render json: { data: record.as_json }, status: status
        elsif record.errors.added?(:rating, :rating_required)
          render json: { error: "rating_required", message: "A score is required to publish a review." },
            status: :unprocessable_content
        else
          raise ActiveRecord::RecordInvalid, record
        end
      end

      def readable_review
        review = UserGameReview.find(params[:id])
        return review if review.published? || reads_drafts_of?(review.user_id)

        raise ActiveRecord::RecordNotFound, "not_found"
      end

      def reads_drafts_of?(user_id)
        return false unless current_principal&.discord_user?

        current_principal.id.to_s == user_id.to_s || admin_or_above?
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameReview.find_by(review_id: params[:id])&.user_id
      end
    end
  end
end

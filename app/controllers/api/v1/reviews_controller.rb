# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      # Caller-settable columns. `user_id` comes from the path (or the existing
      # record) and the key is generated, so neither is accepted in the body.
      WRITABLE_ATTRS = %w[gamedb_game_id title body rating facets is_shared].freeze

      def index
        scope = UserGameReview.where(user_id: params[:user_id])
        render_collection(scope, default_order: { created_at: :desc })
      end

      def game_index
        scope = UserGameReview.where(gamedb_game_id: params[:id]).includes(:user)
        render_collection(scope, resource: ReviewUserEntryResource,
          default_order: Arel.sql("(body IS NOT NULL) DESC, created_at DESC"))
      end

      def show
        render json: { data: UserGameReview.find(params[:id]).as_json }
      end

      def create
        record = UserGameReview.create!(writable_data.merge("user_id" => params[:user_id]))
        render json: { data: record.as_json }, status: :created
      end

      def update
        record = UserGameReview.find(params[:id])
        record.update!(writable_data)
        render json: { data: record.as_json }
      end

      def destroy
        UserGameReview.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def writable_data
        request_data.slice(*WRITABLE_ATTRS)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameReview.find_by(review_id: params[:id])&.user_id
      end
    end
  end
end

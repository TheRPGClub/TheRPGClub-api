# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserGameReview.where(user_id: params[:user_id])
        records = scope
          .order(created_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: records.as_json,
          meta: { limit: pagination_limit, offset: pagination_offset }
        }
      end

      def game_index
        entries = UserGameReview
          .where(gamedb_game_id: params[:id])
          .includes(:user)
          .order(Arel.sql("(body IS NOT NULL) DESC, created_at DESC"))
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: ReviewUserEntryResource.new(entries).serializable_hash,
          meta: { limit: pagination_limit, offset: pagination_offset }
        }
      end

      def show
        render json: { data: UserGameReview.find(params[:id]).as_json }
      end

      def create
        record = UserGameReview.create!(request_data.merge("user_id" => params[:user_id]))
        render json: { data: record.as_json }, status: :created
      end

      def update
        record = UserGameReview.find(params[:id])
        record.update!(request_data)
        render json: { data: record.as_json }
      end

      def destroy
        UserGameReview.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameReview.find_by(review_id: params[:id])&.user_id
      end
    end
  end
end

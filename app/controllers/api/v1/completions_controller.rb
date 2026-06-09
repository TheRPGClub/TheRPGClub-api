# frozen_string_literal: true

module Api
  module V1
    class CompletionsController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserGameCompletion.where(user_id: params[:user_id]).preload(:game, :platform)
        total = scope.count
        records = scope
          .order(completed_at: :desc, created_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: CompletionEntryResource.new(records).serializable_hash,
          meta: { limit: pagination_limit, offset: pagination_offset, total: total }
        }
      end

      def game_index
        entries = UserGameCompletion
          .where(gamedb_game_id: params[:id])
          .includes(:user)
          .order(completed_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: CompletionUserEntryResource.new(entries).serializable_hash,
          meta: { limit: pagination_limit, offset: pagination_offset }
        }
      end

      def show
        record = UserGameCompletion.includes(:game, :platform).find(params[:id])
        render json: { data: CompletionEntryResource.new(record).serializable_hash }
      end

      def create
        record = UserGameCompletion.create!(request_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: CompletionEntryResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = UserGameCompletion.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: CompletionEntryResource.new(record).serializable_hash }
      end

      def destroy
        UserGameCompletion.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameCompletion.find_by(completion_id: params[:id])&.user_id
      end
    end
  end
end

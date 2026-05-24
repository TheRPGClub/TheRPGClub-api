# frozen_string_literal: true

module Api
  module V1
    class CompletionsController < ApplicationController
      include GameEntrySerialization

      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserGameCompletion.where(user_id: params[:user_id]).preload(:game, :platform)
        total = scope.count
        records = scope
          .order(completed_at: :desc, created_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: records.map { |entry| serialize_with_game_and_platform(entry) },
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
          data: entries.map { |e| e.as_json.merge("user" => e.user&.as_json(except: RpgClubUser::BINARY_COLUMNS)) },
          meta: { limit: pagination_limit, offset: pagination_offset }
        }
      end

      def show
        record = UserGameCompletion.includes(:game, :platform).find(params[:id])
        render json: { data: serialize_with_game_and_platform(record) }
      end

      def create
        record = UserGameCompletion.create!(request_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: serialize_with_game_and_platform(record) }, status: :created
      end

      def update
        record = UserGameCompletion.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: serialize_with_game_and_platform(record) }
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

# frozen_string_literal: true

module Api
  module V1
    class FavoritesController < ApplicationController
      include GameEntrySerialization

      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserGameFavorite.where(user_id: params[:user_id]).preload(:game)
        total = scope.count
        records = scope
          .order(sort_order: :asc, created_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: records.map { |entry| serialize_with_game(entry) },
          meta: { limit: pagination_limit, offset: pagination_offset, total: total }
        }
      end

      def show
        record = UserGameFavorite.includes(:game).find(params[:id])
        render json: { data: serialize_with_game(record) }
      end

      def create
        record = UserGameFavorite.create!(request_data.merge("user_id" => params[:user_id]))
        # The newly-created record needs a reload so the `:game` association
        # is materialized for the serializer (otherwise it would re-query
        # lazily during JSON encoding, which is fine but masks load failures).
        record.reload
        render json: { data: serialize_with_game(record) }, status: :created
      end

      def update
        record = UserGameFavorite.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: serialize_with_game(record) }
      end

      def destroy
        UserGameFavorite.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameFavorite.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end

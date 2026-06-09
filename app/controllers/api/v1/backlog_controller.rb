# frozen_string_literal: true

module Api
  module V1
    class BacklogController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserGameBacklog.where(user_id: params[:user_id]).preload(:game, :platform)
        total = scope.count
        records = scope
          .order(sort_order: :asc, created_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: BacklogEntryResource.new(records).serializable_hash,
          meta: { limit: pagination_limit, offset: pagination_offset, total: total }
        }
      end

      def show
        record = UserGameBacklog.includes(:game, :platform).find(params[:id])
        render json: { data: BacklogEntryResource.new(record).serializable_hash }
      end

      def create
        record = UserGameBacklog.create!(request_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: BacklogEntryResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = UserGameBacklog.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: BacklogEntryResource.new(record).serializable_hash }
      end

      def destroy
        UserGameBacklog.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameBacklog.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end

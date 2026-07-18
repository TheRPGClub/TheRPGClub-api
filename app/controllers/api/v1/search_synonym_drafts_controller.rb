# frozen_string_literal: true

module Api
  module V1
    class SearchSynonymDraftsController < ApplicationController
      def index
        scope = GamedbSearchSynonymDraft.all
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        render_collection(scope, resource: SearchSynonymDraftResource, default_order: { updated_at: :desc })
      end

      def show
        render json: { data: SearchSynonymDraftResource.new(GamedbSearchSynonymDraft.find(params[:id])).serializable_hash }
      end

      def create
        return unless require_admin_or_service!

        record = GamedbSearchSynonymDraft.create!(request_data)
        render json: { data: SearchSynonymDraftResource.new(record).serializable_hash }, status: :created
      end

      def update
        return unless require_admin_or_service!

        record = GamedbSearchSynonymDraft.find(params[:id])
        record.update!(request_data)
        render json: { data: SearchSynonymDraftResource.new(record).serializable_hash }
      end

      def destroy
        return unless require_admin_or_service!

        GamedbSearchSynonymDraft.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

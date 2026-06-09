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
        render json: { data: GamedbSearchSynonymDraft.find(params[:id]).as_json }
      end

      def create
        return unless require_admin_or_service!

        record = GamedbSearchSynonymDraft.create!(request_data)
        render json: { data: record.as_json }, status: :created
      end

      def update
        return unless require_admin_or_service!

        record = GamedbSearchSynonymDraft.find(params[:id])
        record.update!(request_data)
        render json: { data: record.as_json }
      end

      def destroy
        return unless require_admin_or_service!

        GamedbSearchSynonymDraft.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

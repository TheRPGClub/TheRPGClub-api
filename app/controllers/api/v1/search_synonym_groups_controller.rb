# frozen_string_literal: true

module Api
  module V1
    class SearchSynonymGroupsController < ApplicationController
      def index
        render_collection(GamedbSearchSynonymGroup.all, resource: SearchSynonymGroupResource, default_order: { group_id: :asc })
      end

      def show
        render json: { data: GamedbSearchSynonymGroup.find(params[:id]).as_json }
      end

      def create
        return unless require_admin_or_service!

        record = GamedbSearchSynonymGroup.create!(request_data)
        render json: { data: record.as_json }, status: :created
      end

      def update
        return unless require_admin_or_service!

        record = GamedbSearchSynonymGroup.find(params[:id])
        record.update!(request_data)
        render json: { data: record.as_json }
      end

      def destroy
        return unless require_admin_or_service!

        GamedbSearchSynonymGroup.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

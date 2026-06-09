# frozen_string_literal: true

module Api
  module V1
    class SearchSynonymsController < ApplicationController
      def index
        scope = GamedbSearchSynonym.all
        scope = scope.where(group_id: params[:group_id]) if params[:group_id].present?
        render_collection(scope, resource: SearchSynonymResource, default_order: { group_id: :asc, term_text: :asc })
      end

      def show
        render json: { data: GamedbSearchSynonym.find(params[:id]).as_json }
      end

      def create
        return unless require_admin_or_service!

        record = GamedbSearchSynonym.create!(request_data)
        render json: { data: record.as_json }, status: :created
      end

      def update
        return unless require_admin_or_service!

        record = GamedbSearchSynonym.find(params[:id])
        record.update!(request_data)
        render json: { data: record.as_json }
      end

      def destroy
        return unless require_admin_or_service!

        GamedbSearchSynonym.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

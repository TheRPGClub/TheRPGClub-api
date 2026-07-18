# frozen_string_literal: true

module Api
  module V1
    class SuggestionsController < ApplicationController
      def index
        render_collection(RpgClubSuggestion.all, resource: SuggestionResource, default_order: { created_at: :desc })
      end

      def show
        render json: { data: SuggestionResource.new(RpgClubSuggestion.find(params[:id])).serializable_hash }
      end

      def create
        record = RpgClubSuggestion.create!(request_data)
        render json: { data: SuggestionResource.new(record).serializable_hash }, status: :created
      end

      def destroy
        RpgClubSuggestion.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

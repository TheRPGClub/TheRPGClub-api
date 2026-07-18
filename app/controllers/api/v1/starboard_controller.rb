# frozen_string_literal: true

module Api
  module V1
    class StarboardController < ApplicationController
      def index
        render_collection(RpgClubStarboardEntry.all, resource: StarboardEntryResource, default_order: { created_at: :desc })
      end

      def show
        render json: { data: StarboardEntryResource.new(RpgClubStarboardEntry.find(params[:message_id])).serializable_hash }
      end

      def create
        record = RpgClubStarboardEntry.create!(request_data)
        render json: { data: StarboardEntryResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = RpgClubStarboardEntry.find(params[:message_id])
        record.update!(request_data)
        render json: { data: StarboardEntryResource.new(record).serializable_hash }
      end

      def destroy
        RpgClubStarboardEntry.find(params[:message_id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

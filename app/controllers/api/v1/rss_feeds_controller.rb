# frozen_string_literal: true

module Api
  module V1
    class RssFeedsController < ApplicationController
      def index
        render_collection(RpgClubRssFeed.all, resource: RssFeedResource, default_order: { feed_name: :asc })
      end

      def show
        render json: { data: RssFeedResource.new(RpgClubRssFeed.find(params[:id])).serializable_hash }
      end

      def create
        record = RpgClubRssFeed.create!(request_data)
        render json: { data: RssFeedResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = RpgClubRssFeed.find(params[:id])
        record.update!(request_data)
        render json: { data: RssFeedResource.new(record).serializable_hash }
      end

      def destroy
        RpgClubRssFeed.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    class VotingInfoController < ApplicationController
      def index
        render_collection(BotVotingInfo.all, resource: VotingInfoResource, default_order: { round_number: :desc })
      end

      # GET /api/v1/voting_info/current
      #
      # Returns the current (highest `round_number`) round, or 404 if none
      # exist. Saves the bot's getCurrentRound() from fetching the full list
      # just to read the newest row. Open to any authenticated caller, like
      # #index/#show. `first!` routes the empty case through render_not_found.
      def current
        record = BotVotingInfo.order(round_number: :desc).first!
        render json: { data: VotingInfoResource.new(record).serializable_hash }
      end

      def show
        record = BotVotingInfo.find(params[:id])
        render json: { data: VotingInfoResource.new(record).serializable_hash }
      end

      def create
        record = BotVotingInfo.create!(request_data)
        render json: { data: VotingInfoResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = BotVotingInfo.find(params[:id])
        record.update!(request_data)
        render json: { data: VotingInfoResource.new(record).serializable_hash }
      end

      def destroy
        BotVotingInfo.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end

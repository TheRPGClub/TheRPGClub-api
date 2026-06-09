# frozen_string_literal: true

module Api
  module V1
    class NowPlayingController < ApplicationController
      def index
        entries = UserNowPlaying
          .where(gamedb_game_id: params[:id])
          .includes(:user)
          .order(added_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: NowPlayingUserEntryResource.new(entries).serializable_hash,
          meta: { limit: pagination_limit, offset: pagination_offset }
        }
      end

      def user_index
        scope = UserNowPlaying.where(user_id: params[:user_id]).preload(:game, :platform)
        total = scope.count
        records = scope
          .order(added_at: :desc)
          .limit(pagination_limit)
          .offset(pagination_offset)

        render json: {
          data: NowPlayingEntryResource.new(records).serializable_hash,
          meta: { limit: pagination_limit, offset: pagination_offset, total: total }
        }
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    class FavoritesController < ApplicationController
      include ShelfPositioning

      before_action :require_owner!, only: %i[create update destroy]

      # Caller-settable columns. `user_id` comes from the path (or the existing
      # record) and the key is generated, so neither is accepted in the body.
      WRITABLE_ATTRS = %w[gamedb_game_id note sort_order].freeze

      # `game_id` (optional) narrows to one game's entry by exact
      # `gamedb_game_id`, so the game page need not read the whole list.
      def index
        scope = UserGameFavorite.where(user_id: params[:user_id]).preload(:game)
        scope = scope.where(gamedb_game_id: params[:game_id]) if params[:game_id].present?
        render_collection(scope, resource: FavoriteEntryResource, default_order: UserGameFavorite::SHELF_ORDER)
      end

      def show
        record = UserGameFavorite.includes(:game).find(params[:id])
        render json: { data: FavoriteEntryResource.new(record).serializable_hash }
      end

      def create
        record = UserGameFavorite.create!(writable_data.merge("user_id" => params[:user_id]))
        # The newly-created record needs a reload so the `:game` association
        # is materialized for the serializer (otherwise it would re-query
        # lazily during JSON encoding, which is fine but masks load failures).
        record.reload
        render json: { data: FavoriteEntryResource.new(record).serializable_hash }, status: :created
      end

      # A `position` (1-based) moves the entry within the member's list and
      # renumbers the rest (ShelfOrder), alongside any other changed fields.
      def update
        position = shelf_position
        return if performed?

        record = UserGameFavorite.find(params[:id])
        ActiveRecord::Base.transaction do
          record.update!(writable_data)
          record.move_to_position!(position) if position
        end
        record.reload
        render json: { data: FavoriteEntryResource.new(record).serializable_hash }
      end

      def destroy
        UserGameFavorite.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def writable_data
        request_data.slice(*WRITABLE_ATTRS)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameFavorite.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end

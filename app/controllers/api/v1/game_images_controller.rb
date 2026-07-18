# frozen_string_literal: true

module Api
  module V1
    class GameImagesController < ApplicationController
      before_action :set_game

      def index
        render json: { data: GameImageResource.new(@game.images.primary_first).serializable_hash }
      end

      def create
        return unless require_admin_or_service!

        image = Gamedb::GameImageStorage.new.upload_manual!(
          game: @game,
          uploaded_file: image_params.fetch(:file),
          kind: image_params.fetch(:kind),
          uploaded_by_user_id: current_principal.discord_user? ? current_principal.id : nil,
          primary: boolean_param(image_params[:is_primary], default: true)
        )
        bump_relations_cache_version!

        render json: { data: GameImageResource.new(image).serializable_hash }, status: :created
      rescue KeyError, Gamedb::GameImageStorage::InvalidImageError => error
        render json: { error: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::ConfigurationError => error
        render json: { error: "backblaze_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::RequestError => error
        render json: { error: "backblaze_request_failed", message: error.message }, status: :bad_gateway
      end

      def update
        return unless require_admin_or_service!

        image = @game.images.find(params[:id])
        attrs = update_params

        GamedbGameImage.transaction do
          if boolean_param(attrs[:is_primary], default: false)
            @game.images.where(kind: image.kind, is_primary: true).where.not(image_id: image.image_id).update_all(
              is_primary: false,
              updated_at: Time.current
            )
          end
          image.update!(attrs)
        end
        bump_relations_cache_version!

        render json: { data: GameImageResource.new(image).serializable_hash }
      end

      def destroy
        return unless require_admin_or_service!

        image = @game.images.find(params[:id])
        Gamedb::GameImageStorage.new.delete!(image)
        bump_relations_cache_version!
        render json: { deleted: true }
      rescue Backblaze::Client::ConfigurationError => error
        render json: { error: "backblaze_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::RequestError => error
        render json: { error: "backblaze_request_failed", message: error.message }, status: :bad_gateway
      end

      private

      def set_game
        @game = GamedbGame.find(params[:game_id])
      end

      # relations_data never renders this game's own images, only another
      # game's cached `alternates` slice does (via GameResource) -- bump the
      # shared version so those caches invalidate (GamesController#relations_data).
      def bump_relations_cache_version!
        Gamedb::GameRelationsCacheVersion.bump!
      end

      def image_params
        params.require(:image).permit(:file, :kind, :is_primary)
      end

      def update_params
        params.require(:data).permit(:is_primary, :position).to_h
      end

      def boolean_param(value, default:)
        return default if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end

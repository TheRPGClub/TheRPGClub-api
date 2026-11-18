# frozen_string_literal: true

module Api
  module V1
    module Codex
      # A Club Codex entry's images (spec #397, ticket #410): a gallery of up
      # to 4 on a History Event or Lore Entry, added and removed by whoever
      # can edit the entry (ClubCodex::Actor); Fun Facts refuse images. The
      # files are kept by ClubCodex::Images.
      #
      # The upload returns the image's id and url, so the website can show it
      # in the gallery or place it in the entry's Plate story.
      class EntryImagesController < BaseController
        before_action :require_acting_member!
        before_action :find_editable_entry

        rescue_from ClubCodex::Images::InvalidImageError do |error|
          render json: { error: "invalid_image", message: error.message }, status: :unprocessable_content
        end
        rescue_from ClubCodex::Images::NotAllowed do |error|
          render json: { error: "images_not_allowed", message: error.message }, status: :unprocessable_content
        end
        rescue_from ClubCodex::Images::GalleryFull do |error|
          render json: { error: "too_many_images", message: error.message }, status: :unprocessable_content
        end

        # POST /api/v1/codex/entries/:entry_id/images
        # Multipart: data[file] (JPEG, PNG, WebP or GIF, at most 10 MB); the
        # bot adds data[acting_user_id].
        def create
          image = ClubCodex::Images.new.add!(@entry, uploaded_file: params.dig(:data, :file),
            uploader_id: actor.user_id)
          render json: { data: image.payload }, status: :created
        end

        # DELETE /api/v1/codex/entries/:entry_id/images/:id
        #
        # Removes the file from storage too; later images move up.
        def destroy
          image = @entry.images.find(params[:id])
          ClubCodex::Images.new.remove!(image)
          render json: { data: { id: image.id, deleted: true } }
        end

        private

        def find_editable_entry
          @entry = CodexEntry.find(params[:entry_id])
          return if actor.can_edit?(@entry)

          forbid(@entry.history_event? ? ClubCodex::Refusals::HISTORY : ClubCodex::Refusals::EDIT)
        end
      end
    end
  end
end

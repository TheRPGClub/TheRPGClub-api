# frozen_string_literal: true

require "securerandom"

module Gamedb
  class GameImageStorage
    class InvalidImageError < StandardError; end

    MAX_UPLOAD_SIZE = 10.megabytes
    CONTENT_TYPE_EXTENSIONS = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/webp" => "webp",
      "image/gif" => "gif"
    }.freeze

    # Checks an uploaded image file (JPEG, PNG, WebP or GIF, at most
    # MAX_UPLOAD_SIZE, not empty) and returns [bytes, content_type]. Shared
    # with LiveEvents::ImageStorage so both keep the same limits.
    def self.read_upload!(uploaded_file)
      raise InvalidImageError, "image file is required" unless uploaded_file.respond_to?(:read)

      content_type = normalized_content_type(uploaded_file.content_type)
      raise InvalidImageError, "image file is too large" if uploaded_file.size.to_i > MAX_UPLOAD_SIZE

      bytes = uploaded_file.read.to_s.b
      raise InvalidImageError, "image file is empty" if bytes.empty?

      [ bytes, content_type ]
    ensure
      uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
    end

    def self.normalized_content_type(content_type)
      value = content_type.to_s.split(";").first.to_s.downcase
      return value if CONTENT_TYPE_EXTENSIONS.key?(value)

      raise InvalidImageError, "image must be JPEG, PNG, WebP, or GIF"
    end

    def initialize(client: Backblaze::Client.new)
      @client = client
    end

    def upload_manual!(game:, uploaded_file:, kind:, uploaded_by_user_id:, primary: true)
      normalized_kind = normalize_kind(kind)
      bytes, content_type = self.class.read_upload!(uploaded_file)
      extension = extension_for(uploaded_file.original_filename, content_type)
      object_key = manual_object_key(game, normalized_kind, extension)

      upload_and_record!(
        game: game,
        kind: normalized_kind,
        object_key: object_key,
        bytes: bytes,
        content_type: content_type,
        uploaded_by_user_id: uploaded_by_user_id,
        primary: primary,
        position: next_position(game, normalized_kind)
      )
    end

    def import_igdb!(game:, kind:, image_url:, position:, primary:)
      normalized_kind = normalize_kind(kind)
      response = Faraday.get(image_url) { |request| request.options.timeout = 30 }
      raise InvalidImageError, "IGDB image download failed with HTTP #{response.status}" unless response.success?

      content_type = self.class.normalized_content_type(response.headers["content-type"])
      extension = CONTENT_TYPE_EXTENSIONS.fetch(content_type, "jpg")
      object_key = igdb_object_key(game, normalized_kind, position, extension)

      upload_and_record!(
        game: game,
        kind: normalized_kind,
        object_key: object_key,
        bytes: response.body.to_s.b,
        content_type: content_type,
        uploaded_by_user_id: nil,
        primary: primary,
        position: position
      )
    end

    def delete!(image)
      @client.delete_file(object_key: image.object_key)
      image.destroy!
    end

    def delete_all_for_game!(game)
      GamedbGameImage.where(game_id: game.game_id).find_each do |image|
        delete!(image)
      end
    end

    private

    def upload_and_record!(game:, kind:, object_key:, bytes:, content_type:, uploaded_by_user_id:, primary:, position:)
      @client.upload_bytes(object_key: object_key, bytes: bytes, content_type: content_type)

      GamedbGameImage.transaction do
        clear_primary!(game, kind) if primary
        image = GamedbGameImage.find_or_initialize_by(object_key: object_key)
        image.assign_attributes(
          game_id: game.game_id,
          kind: kind,
          uploaded_by_user_id: uploaded_by_user_id,
          is_primary: primary,
          position: position
        )
        image.save!
        image
      end
    end

    def clear_primary!(game, kind)
      GamedbGameImage
        .where(game_id: game.game_id, kind: kind, is_primary: true)
        .update_all(is_primary: false, updated_at: Time.current)
    end

    def normalize_kind(kind)
      value = kind.to_s.strip
      return value if GamedbGameImage::KINDS.include?(value)

      raise InvalidImageError, "kind must be one of: #{GamedbGameImage::KINDS.join(', ')}"
    end

    def extension_for(original_filename, content_type)
      extension = File.extname(original_filename.to_s).delete_prefix(".").downcase
      return extension if CONTENT_TYPE_EXTENSIONS.value?(extension)

      CONTENT_TYPE_EXTENSIONS.fetch(content_type)
    end

    def manual_object_key(game, kind, extension)
      "games/#{game_folder(game)}/#{kind}/manual-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}.#{extension}"
    end

    def igdb_object_key(game, kind, position, extension)
      filename = kind == "cover" ? "main" : format("%03d", position)
      "games/#{game_folder(game)}/#{kind}/#{filename}.#{extension}"
    end

    def game_folder(game)
      slug = game.slug.presence || game.title.to_s.parameterize
      "#{game.game_id}-#{slug.presence || 'game'}"
    end

    def next_position(game, kind)
      GamedbGameImage.where(game_id: game.game_id, kind: kind).maximum(:position).to_i + 1
    end
  end
end

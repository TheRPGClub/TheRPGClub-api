# frozen_string_literal: true

require "securerandom"

module LiveEvents
  # Stores a live event's uploaded image in Backblaze and returns its public
  # URL, which the bot downloads for the scheduled event and shows in the
  # thread. Same limits as a game image upload.
  class ImageStorage
    class InvalidImageError < StandardError; end

    MAX_UPLOAD_SIZE = Gamedb::GameImageStorage::MAX_UPLOAD_SIZE
    CONTENT_TYPE_EXTENSIONS = Gamedb::GameImageStorage::CONTENT_TYPE_EXTENSIONS

    def initialize(client: Backblaze::Client.new)
      @client = client
    end

    # Raises InvalidImageError for a bad file, Backblaze::Client errors for a
    # failed or unconfigured upload.
    def upload!(uploaded_file, now: Time.current)
      raise InvalidImageError, "image must be a file upload" unless uploaded_file.respond_to?(:read)

      content_type = uploaded_file.content_type.to_s.split(";").first.to_s.downcase
      extension = CONTENT_TYPE_EXTENSIONS[content_type]
      raise InvalidImageError, "image must be JPEG, PNG, WebP, or GIF" unless extension
      raise InvalidImageError, "image file is too large" if uploaded_file.size.to_i > MAX_UPLOAD_SIZE

      bytes = uploaded_file.read.to_s.b
      raise InvalidImageError, "image file is empty" if bytes.empty?

      object_key = "live-events/#{now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}.#{extension}"
      public_url = Backblaze::Client.public_url_for(object_key)
      raise Backblaze::Client::ConfigurationError, "BACKBLAZE_PUBLIC_BASE_URL must be set" if public_url.blank?

      @client.upload_bytes(object_key: object_key, bytes: bytes, content_type: content_type)
      public_url
    end
  end
end

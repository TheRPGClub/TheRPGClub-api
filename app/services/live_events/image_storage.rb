# frozen_string_literal: true

require "securerandom"

module LiveEvents
  # Stores a live event's uploaded image in Backblaze and returns its public
  # URL, which the bot downloads for the scheduled event and shows in the
  # thread. Same limits as a game image upload.
  class ImageStorage
    InvalidImageError = Gamedb::GameImageStorage::InvalidImageError

    def initialize(client: Backblaze::Client.new)
      @client = client
    end

    # Raises InvalidImageError for a bad file, Backblaze::Client errors for a
    # failed or unconfigured upload.
    def upload!(uploaded_file, now: Time.current)
      bytes, content_type = Gamedb::GameImageStorage.read_upload!(uploaded_file)
      extension = Gamedb::GameImageStorage::CONTENT_TYPE_EXTENSIONS.fetch(content_type)

      object_key = "live-events/#{now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}.#{extension}"
      public_url = Backblaze::Client.public_url_for(object_key)
      raise Backblaze::Client::ConfigurationError, "BACKBLAZE_PUBLIC_BASE_URL must be set" if public_url.blank?

      @client.upload_bytes(object_key: object_key, bytes: bytes, content_type: content_type)
      public_url
    end
  end
end

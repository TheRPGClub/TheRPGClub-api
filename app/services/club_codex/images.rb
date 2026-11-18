# frozen_string_literal: true

require "securerandom"

module ClubCodex
  # A Club Codex entry's images (spec #397, ticket #410), kept in the
  # Backblaze bucket the GameDB game images use, with the same file limits
  # (Gamedb::GameImageStorage.read_upload!).
  #
  # History Events and Lore Entries hold up to CodexEntryImage::MAX_PER_ENTRY;
  # Fun Facts hold none. An image's position follows upload order: removing
  # one moves the later ones up, so a gallery is always 1..n. Uploads and
  # removals on one entry take turns (the entry row is locked), so two
  # uploads at once can't make a fifth.
  #
  # An added image's id and url can also be placed in the entry's Plate
  # story, should the website show images inline.
  class Images
    InvalidImageError = Gamedb::GameImageStorage::InvalidImageError

    # The entry's part takes no images (a Fun Fact).
    class NotAllowed < StandardError
      def initialize(msg = "Fun Facts can't have images.") = super
    end

    # The entry already has the most images it may.
    class GalleryFull < StandardError
      def initialize(msg = "An entry can have at most #{CodexEntryImage::MAX_PER_ENTRY} images.") = super
    end

    def initialize(client: Backblaze::Client.new)
      @client = client
    end

    # Stores `uploaded_file` as the entry's next image and returns the
    # CodexEntryImage. Raises NotAllowed, GalleryFull, InvalidImageError for
    # a bad file, and Backblaze::Client errors for a failed or unconfigured
    # upload; nothing is kept when any of them is raised.
    def add!(entry, uploaded_file:, uploader_id:, now: Time.current)
      raise NotAllowed if entry.fun_fact?
      raise GalleryFull if full?(entry.id)

      bytes, content_type = Gamedb::GameImageStorage.read_upload!(uploaded_file)
      extension = Gamedb::GameImageStorage::CONTENT_TYPE_EXTENSIONS.fetch(content_type)
      object_key = "codex/entries/#{entry.id}/#{now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}.#{extension}"
      if Backblaze::Client.public_url_for(object_key).blank?
        raise Backblaze::Client::ConfigurationError, "BACKBLAZE_PUBLIC_BASE_URL must be set"
      end

      @client.upload_bytes(object_key: object_key, bytes: bytes, content_type: content_type)
      record!(entry.id, object_key, uploader_id)
    end

    # Removes the image's file, then the image, moving the later ones up.
    # A storage failure raises and keeps the image, so it can be retried.
    def remove!(image)
      @client.delete_file(object_key: image.object_key)
      CodexEntryImage.transaction do
        CodexEntry.lock.find(image.entry_id)
        image = CodexEntryImage.find(image.id)
        image.destroy!
        CodexEntryImage.where(entry_id: image.entry_id).where("position > ?", image.position)
          .update_all("position = position - 1") # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # Removes every image of the entry, before the entry itself is deleted.
    # Last first, so a failure part way leaves a gallery still 1..n.
    def remove_all!(entry)
      CodexEntryImage.where(entry_id: entry.id).order(position: :desc).each { |image| remove!(image) }
    end

    private

    def full?(entry_id) = CodexEntryImage.where(entry_id: entry_id).count >= CodexEntryImage::MAX_PER_ENTRY

    # Records the stored file as the entry's next image; an entry that filled
    # up, or went, meanwhile gets the file removed again.
    def record!(entry_id, object_key, uploader_id)
      CodexEntryImage.transaction do
        CodexEntry.lock.find(entry_id)
        count = CodexEntryImage.where(entry_id: entry_id).count
        raise GalleryFull if count >= CodexEntryImage::MAX_PER_ENTRY

        CodexEntryImage.create!(entry_id: entry_id, object_key: object_key, position: count + 1,
          uploaded_by_user_id: uploader_id)
      end
    rescue GalleryFull, ActiveRecord::RecordNotFound
      @client.delete_file(object_key: object_key)
      raise
    end
  end
end

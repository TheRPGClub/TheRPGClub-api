# frozen_string_literal: true

require "securerandom"

# A Bug Report's one optional screenshot (spec api#498, ticket api#500),
# kept in the Backblaze bucket the GameDB game images use. Only Pending Bug
# Reports take one; it can be replaced or removed until review.
#
# The row is changed under its lock (re-checking Pending), and the file of a
# replaced or removed screenshot goes after: a storage failure then leaves an
# unused file behind (logged), never a screenshot pointing at nothing.
class FeedbackScreenshots
  class InvalidImageError < StandardError; end

  # Only Bug Reports carry a screenshot.
  class NotAllowed < StandardError
    def initialize(msg = "Only Bug Reports can have a screenshot.") = super
  end

  # The Feedback was reviewed or withdrawn.
  class NotPending < StandardError; end

  MAX_SIZE = 5.megabytes
  # The accepted types, told by the file's leading bytes rather than the
  # declared content type.
  SIGNATURES = {
    "image/png" => ->(head) { head.start_with?("\x89PNG\r\n\x1A\n".b) },
    "image/jpeg" => ->(head) { head.start_with?("\xFF\xD8\xFF".b) },
    "image/webp" => ->(head) { head.start_with?("RIFF".b) && head.byteslice(8, 4) == "WEBP".b }
  }.freeze
  EXTENSIONS = { "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp" }.freeze

  def initialize(client: Backblaze::Client.new)
    @client = client
  end

  # Stores `uploaded_file` as the Feedback's screenshot, replacing any it
  # had. Raises NotAllowed, NotPending, InvalidImageError, or a
  # Backblaze::Client error; nothing is changed when any is raised.
  def attach!(feedback, uploaded_file:, now: Time.current)
    raise NotAllowed unless feedback.bug_report?
    raise not_pending(feedback) unless feedback.pending?

    bytes, content_type = read!(uploaded_file)
    object_key = "feedback/#{feedback.feedback_id}/#{now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}." \
                 "#{EXTENSIONS.fetch(content_type)}"
    if Backblaze::Client.public_url_for(object_key).blank?
      raise Backblaze::Client::ConfigurationError, "BACKBLAZE_PUBLIC_BASE_URL must be set"
    end

    @client.upload_bytes(object_key: object_key, bytes: bytes, content_type: content_type)
    begin
      previous = swap!(feedback, object_key) { raise NotAllowed unless feedback.bug_report? }
    rescue StandardError
      discard(object_key)
      raise
    end
    discard(previous)
  end

  # Removes the Feedback's screenshot, if any. Raises NotPending.
  def remove!(feedback)
    previous = swap!(feedback, nil)
    discard(previous)
  end

  # Deletes a file no longer used (a replaced screenshot, or one dropped by
  # a kind change); a failure only leaves it behind, logged.
  def discard(object_key)
    return if object_key.blank?

    @client.delete_file(object_key: object_key)
  rescue Backblaze::Client::ConfigurationError, Backblaze::Client::RequestError => error
    Rails.logger.warn({ event: "feedback_screenshot.discard_failed", object_key: object_key,
                        error: error.message }.to_json)
  end

  private

  # Sets the screenshot under the row lock while Pending and returns the
  # previous key. The block runs under the lock, for extra checks.
  def swap!(feedback, object_key)
    feedback.with_lock do
      raise not_pending(feedback) unless feedback.pending?

      yield if block_given?
      previous = feedback.screenshot_key
      feedback.update!(screenshot_key: object_key)
      previous
    end
  end

  def read!(uploaded_file)
    raise InvalidImageError, "image file is required" unless uploaded_file.respond_to?(:read)
    raise InvalidImageError, "screenshot must be at most 5 MB" if uploaded_file.size.to_i > MAX_SIZE

    bytes = uploaded_file.read.to_s.b
    raise InvalidImageError, "image file is empty" if bytes.empty?
    raise InvalidImageError, "screenshot must be at most 5 MB" if bytes.bytesize > MAX_SIZE

    content_type = SIGNATURES.find { |_type, matches| matches.call(bytes.byteslice(0, 16)) }&.first
    raise InvalidImageError, "screenshot must be a PNG, JPEG or WebP image" unless content_type

    [ bytes, content_type ]
  ensure
    uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
  end

  def not_pending(feedback) = NotPending.new("feedback is #{feedback.status}, not pending")
end

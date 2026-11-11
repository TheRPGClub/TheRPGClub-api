# frozen_string_literal: true

# A News Item (GLOSSARY.md, "News Hub"; spec #355): a message a member posted
# in a News Category's thread that carries a link, an image, or both. The bot
# records it through the API, keyed on the Discord message id; recording the
# same message again updates it (NewsItem.record!), and removal is a hard
# delete.
#
# The News Category comes from the thread (docs/adr/0006). It may be empty
# only for an imported News Item (`origin` "import") that staff have not
# sorted yet, and such an item is never shown to members (`listed`).
#
# The author need not have a member record: `author_name` is the name they
# had when the message was recorded, shown when there is no record.
class NewsItem < ApplicationRecord
  ORIGINS = %w[live import].freeze
  SNOWFLAKE = /\A\d{1,30}\z/
  WEB_URL = %r{\Ahttps?://\S+\z}i
  LINK_FIELDS = %w[url title site_name description image_url].freeze

  validates :message_id, :channel_id, :author_id, format: { with: SNOWFLAKE, message: "must be a Discord id" }
  validates :author_name, presence: true, length: { maximum: 100 }
  validates :origin, inclusion: { in: ORIGINS }
  validates :posted_at, presence: true
  validates :category_key, inclusion: { in: NewsCategory.keys, message: "is not a News Category" }, allow_nil: true
  validates :category_key, presence: { message: "is required unless the News Item is imported" },
    unless: -> { origin == "import" }
  validates :link_url, presence: { message: "is required when the link has a preview" },
    if: -> { [ link_title, link_site_name, link_description, link_image_url ].any?(&:present?) }
  validates :link_url, :link_image_url, format: { with: WEB_URL, message: "must be an http(s) address" },
    allow_blank: true
  validate :images_are_addresses_with_expiry
  validate :has_link_or_image

  normalizes :comment, :link_url, :link_title, :link_site_name, :link_description, :link_image_url,
    with: ->(value) { value.strip.presence }

  # The News Items members may see: every one with a News Category.
  scope :listed, -> { where.not(category_key: nil) }
  # The News Import's items (ticket #359), and those staff have not sorted.
  scope :imported, -> { where(origin: "import") }
  scope :unsorted, -> { imported.where(category_key: nil) }

  # Records the message `message_id` from the bot's payload, creating the
  # News Item or updating the one already recorded. Returns [item, created].
  #
  # `attrs` holds the writable fields: channel_id, category_key, author_id,
  # author_name, comment, posted_at, edited_at, link (a Hash of LINK_FIELDS,
  # or nil for no link) and images (an Array of { url, expires_at }, where a
  # null expires_at means the address does not expire).
  #
  # A new News Item takes `origin` (the News Import records with "import").
  # An imported News Item keeps its origin and the News Category staff
  # assigned it: recording it again (to renew its image addresses, say)
  # changes everything else.
  def self.record!(message_id, attrs, origin: "live")
    attempts = 0
    begin
      item = find_or_initialize_by(message_id: message_id.to_s)
      created = item.new_record?
      item.assign_payload(attrs, origin: origin)
      item.save!
      [ item, created ]
    rescue ActiveRecord::RecordNotUnique
      # A preview edit raced the message's first recording: update that row.
      attempts += 1
      retry if attempts == 1
      raise
    end
  end

  # Drops the null character from every string in the bot's payload. Discord
  # lets a member type one, and PostgreSQL text and jsonb cannot store it.
  def self.without_null_characters(value)
    case value
    when String then value.delete("\u0000")
    when Hash then value.transform_values { |inner| without_null_characters(inner) }
    when Array then value.map { |inner| without_null_characters(inner) }
    else value
    end
  end

  def assign_payload(attrs, origin: "live")
    attrs = self.class.without_null_characters(attrs.to_h.stringify_keys)
    link = attrs["link"].is_a?(Hash) ? attrs["link"].stringify_keys : {}
    assign_attributes(attrs.slice("channel_id", "author_id", "author_name", "comment", "posted_at", "edited_at"))
    assign_attributes(LINK_FIELDS.to_h { |field| [ "link_#{field}", link[field] ] })
    self.images = Array(attrs["images"]).map { |image| normalize_image(image) }
    self.origin = origin if new_record?
    self.category_key = attrs["category_key"].presence unless imported?
  end

  def imported? = origin == "import"

  # Whether a stored image's Discord address has run out at `now`. Only the
  # message's signed attachment addresses expire: an image with no
  # `expires_at` (an address without Discord's `ex` parameter) never does,
  # nor does the link preview's outside-site image.
  def self.image_expired?(image, now)
    expires_at = image["expires_at"].presence
    expires_at.present? && Time.iso8601(expires_at) <= now
  end

  # Whether any of this News Item's image addresses has run out at `now`.
  def images_expired?(now) = images.any? { |image| self.class.image_expired?(image, now) }

  # The link and the preview Discord generated for it, or nil for no link.
  def link
    return nil if link_url.blank?

    LINK_FIELDS.to_h { |field| [ field, self["link_#{field}"] ] }
  end

  private

  # { "url", "expires_at" } with the expiry in UTC ISO 8601, or nil for an
  # address that does not expire. An expiry that is not a time, or anything
  # else, is kept as given for images_are_addresses_with_expiry to reject.
  def normalize_image(image)
    image = image.to_h if image.respond_to?(:permitted?)
    return image unless image.is_a?(Hash)

    image = image.stringify_keys
    expires_at = image["expires_at"].presence
    expires_at = parse_time(expires_at)&.utc&.iso8601 || expires_at if expires_at
    { "url" => image["url"].to_s.strip, "expires_at" => expires_at }
  end

  def images_are_addresses_with_expiry
    return errors.add(:images, "must be a list") unless images.is_a?(Array)

    images.each_with_index do |image, index|
      next errors.add(:images, "[#{index}] must be an object with url and expires_at") unless image.is_a?(Hash)

      errors.add(:images, "[#{index}] url must be an http(s) address") unless image["url"].to_s.match?(WEB_URL)
      next if image["expires_at"].nil? || parse_time(image["expires_at"])

      errors.add(:images, "[#{index}] expires_at must be an ISO 8601 time or null")
    end
  end

  def has_link_or_image
    return if link_url.present? || (images.is_a?(Array) && images.any?)

    errors.add(:base, "A News Item needs a link or at least one image")
  end

  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end

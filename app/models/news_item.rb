# frozen_string_literal: true

# A News Item (GLOSSARY.md, "News Hub"; spec #355): a message a member posted
# in the News Channel that carries a link, an image, or both. The bot records
# it through the API, keyed on the Discord message id; recording the same
# message again updates it (NewsItem.record!), and removal is a hard delete.
#
# The bot picks the News Category when the item is posted (docs/adr/0007)
# and keeps the pick in `picked_category_key`. The author or staff may
# change the category afterwards (change_category!, ticket #369), which
# records who changed it last and when (`category_changed_by`,
# `category_changed_at`) and leaves the pick as it was, so the bot's misses
# can be listed to refresh its rules. The category may be empty
# only for an imported News Item (`origin` "import") that staff have not
# sorted yet, and such an item is never shown to members (`listed`).
#
# The News Copy, the bot's copy in the category's thread (spec #367, ticket
# #368), lives at `news_copy_message_id` in thread `news_copy_thread_id`:
# both set, or both empty while the item has no News Copy.
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
  validates :picked_category_key, inclusion: { in: NewsCategory.keys, message: "is not a News Category" },
    allow_nil: true
  validate :news_copy_is_a_location
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
  # News Items with a News Copy, and those members may see that have none
  # yet: the bot's history copy and retries work through `uncopied`.
  scope :copied, -> { where.not(news_copy_message_id: nil) }
  scope :uncopied, -> { listed.where(news_copy_message_id: nil) }

  # Records the message `message_id` from the bot's payload, creating the
  # News Item or updating the one already recorded. Returns [item, created].
  #
  # `attrs` holds the writable fields: channel_id, category_key, author_id,
  # author_name, comment, posted_at, edited_at, link (a Hash of LINK_FIELDS,
  # or nil for no link) and images (an Array of { url, expires_at }, where a
  # null expires_at means the address does not expire); and, optionally,
  # picked_category_key and news_copy ({ message_id, thread_id }, or nil for
  # no News Copy), which keep their stored values when omitted, as
  # category_key does when updating a recorded News Item.
  #
  # `attrs` holding only news_copy reports the News Copy's location alone:
  # the recorded News Item changes nothing else (ActiveRecord::RecordNotFound
  # when there is none).
  #
  # A new News Item takes `origin` (the News Import records with "import").
  # An imported News Item keeps its origin and the News Category staff
  # assigned it: recording it again (to renew its image addresses, say)
  # changes everything else.
  def self.record!(message_id, attrs, origin: "live")
    attrs = attrs.to_h.stringify_keys
    return record_news_copy!(message_id, attrs["news_copy"]) if attrs.keys == [ "news_copy" ]

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

  # Stores where the recorded News Item's News Copy lives (`copy`, a Hash
  # of message_id and thread_id, or nil for none), changing nothing else.
  # Returns [item, false].
  def self.record_news_copy!(message_id, copy)
    item = find_by!(message_id: message_id.to_s)
    item.assign_news_copy(copy)
    item.save!
    [ item, false ]
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
    self.category_key = attrs["category_key"].presence if !imported? && (new_record? || attrs.key?("category_key"))
    self.picked_category_key = attrs["picked_category_key"].presence if attrs.key?("picked_category_key")
    assign_news_copy(attrs["news_copy"]) if attrs.key?("news_copy")
  end

  # Sets the News Copy's location from { message_id, thread_id }; nil (or
  # an empty Hash) clears it.
  def assign_news_copy(copy)
    copy = copy.to_h if copy.respond_to?(:permitted?)
    @news_copy_malformed = !copy.nil? && !copy.is_a?(Hash)
    copy = @news_copy_malformed || copy.nil? ? {} : copy.stringify_keys
    self.news_copy_message_id = copy["message_id"].to_s.strip.presence
    self.news_copy_thread_id = copy["thread_id"].to_s.strip.presence
  end

  # Changes the News Category to `key` for the member `by` (a Discord user
  # id; the API checked they may), recording who changed it and when. The
  # bot's first pick (`picked_category_key`) and the News Copy's location
  # are left as they are: the bot moves the copy and reports it. Returns
  # false, changing nothing, when the item is already in that category.
  # Raises ActiveRecord::RecordInvalid for a key that is not a News Category.
  def change_category!(key, by:)
    with_lock do
      changed = category_key != key
      update!(category_key: key, category_changed_by: by, category_changed_at: Time.current) if changed
      changed
    end
  end

  # Where the News Copy lives, { message_id, thread_id }, or nil for none.
  def news_copy
    return nil if news_copy_message_id.blank?

    { "message_id" => news_copy_message_id, "thread_id" => news_copy_thread_id }
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

  def news_copy_is_a_location
    ids = [ news_copy_message_id, news_copy_thread_id ]
    return if !@news_copy_malformed && ids.all?(&:nil?)
    return if ids.all? { |id| id.to_s.match?(SNOWFLAKE) }

    errors.add(:news_copy, "must be null or an object with message_id and thread_id, both Discord ids")
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

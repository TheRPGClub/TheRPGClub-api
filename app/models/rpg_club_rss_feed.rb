# frozen_string_literal: true

class RpgClubRssFeed < ApplicationRecord
  self.table_name = "rpg_club_rss_feeds"
  self.primary_key = "feed_id"

  # Seen-item rows are pure dedup state with no callbacks and no value once
  # their feed is gone (#269). The FK cascades too; this keeps the app's view
  # consistent and avoids relying on the DB alone.
  has_many :items,
    class_name: "RpgClubRssFeedItem",
    foreign_key: :feed_id,
    dependent: :delete_all,
    inverse_of: :feed

  # Only surrounding whitespace is stripped: a trailing slash or letter case can
  # be significant to the server, so those are left as given.
  normalizes :feed_url, with: ->(url) { url.strip }

  validates :feed_name, :feed_url, :channel_id, presence: true
  # Backed by ux_rpg_club_rss_feeds_channel_url; this surfaces a readable 422
  # instead of the generic RecordNotUnique message.
  validates :feed_url, uniqueness: { scope: :channel_id }
end

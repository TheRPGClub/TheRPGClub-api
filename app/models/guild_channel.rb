# frozen_string_literal: true

# A Discord channel in the club's guild, as the bot last reported it (web
# parity 2, #313). The bot replaces the whole list at startup and upserts or
# removes single rows on channel create, update and delete; nothing else
# writes here. `channel_type` is Discord's numeric ChannelType and
# `parent_id` the channel's category (itself a row of type CATEGORY).
class GuildChannel < ApplicationRecord
  self.primary_key = "channel_id"

  CATEGORY = 4
  # Types a reminder or bot message can be posted to: GuildText and
  # GuildAnnouncement.
  TEXT_TYPES = [ 0, 5 ].freeze
  WRITABLE = %w[channel_id name channel_type parent_id position].freeze

  validates :channel_id, :name, presence: true
  validates :channel_type, numericality: { only_integer: true }
  validates :position, numericality: { only_integer: true }

  scope :text, -> { where(channel_type: TEXT_TYPES) }

  # Text channels for pickers, each with its category's name, ordered as
  # Discord shows them: uncategorized first, then by category position, then
  # by channel position.
  def self.text_for_picker
    text
      .joins("LEFT JOIN guild_channels categories ON categories.channel_id = guild_channels.parent_id " \
             "AND categories.channel_type = #{CATEGORY}")
      .select("guild_channels.*, categories.name AS category_name")
      .order(Arel.sql("categories.position ASC NULLS FIRST, guild_channels.position ASC, guild_channels.channel_id ASC"))
  end

  # True when `channel_id` is a synced text channel (for reminder validation).
  def self.text_channel?(channel_id)
    channel_id.present? && text.exists?(channel_id: channel_id.to_s)
  end
end

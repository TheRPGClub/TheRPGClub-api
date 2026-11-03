# frozen_string_literal: true

# A Superadmin's "say" (web parity 2, #337): the bot posts `content` in a
# synced text channel, or replies there to the message a Discord message
# link points at, as the bot's `/superadmin say` does. Queued as a `say`
# BotJob whose payload allows plain user mentions only, so the message can
# never ping @everyone, @here or a role.
class BotSay
  # Discord's message length limit.
  CONTENT_MAX = 2000
  # How much of the content the activity list summary quotes.
  SUMMARY_QUOTE = 80
  ALLOWED_MENTIONS = { "parse" => [ "users" ] }.freeze
  MESSAGE_LINK = %r{\Ahttps://(?:(?:ptb|canary)\.)?discord(?:app)?\.com/channels/(\d+)/(\d+)/(\d+)/?\z}

  class Invalid < StandardError; end

  # Validates and queues the job; raises Invalid with a message for the
  # caller. A blank link means no reply.
  def self.enqueue!(channel_id:, content:, reply_to_message_link: nil, requested_by: nil)
    channel_id = channel_id.to_s.strip
    channel = GuildChannel.text.find_by(channel_id: channel_id) if channel_id.present?
    raise Invalid, "channel_id must be a text channel in the server" unless channel

    content = content.to_s.strip
    raise Invalid, "content can't be blank" if content.empty?
    raise Invalid, "content is too long (at most #{CONTENT_MAX} characters)" if content.length > CONTENT_MAX

    reply_to = parse_link(reply_to_message_link, channel_id)
    verb = reply_to ? "Reply in" : "Say in"
    quote = content.squish.truncate(SUMMARY_QUOTE + 3, separator: " ", omission: "...")

    BotJob.enqueue!(
      kind: "say", summary: "#{verb} ##{channel.name}: \"#{quote}\"", requested_by: requested_by,
      payload: { channel_id: channel_id, content: content, reply_to: reply_to, allowed_mentions: ALLOWED_MENTIONS }
    )
  end

  # The link's channel and message ids, or nil for no link. The reply is
  # posted in the message's channel, so that must be the chosen channel; a
  # link to another guild is refused when the club's guild is configured.
  def self.parse_link(link, channel_id)
    link = link.to_s.strip
    return nil if link.empty?

    match = MESSAGE_LINK.match(link)
    raise Invalid, "reply_to_message_link must be a Discord message link" unless match

    guild_id = ENV["DISCORD_RPGCLUB_GUILD_ID"].to_s.strip
    raise Invalid, "reply_to_message_link is not a message in this server" if guild_id.present? && match[1] != guild_id
    raise Invalid, "reply_to_message_link is not a message in that channel" unless match[2] == channel_id

    { channel_id: match[2], message_id: match[3] }
  end
  private_class_method :parse_link
end

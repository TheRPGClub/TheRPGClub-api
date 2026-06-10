# frozen_string_literal: true

# Serializes a DiscordThread (all columns) plus a computed `jump_url` — the
# Discord deep link to the thread (https://discord.com/channels/<guild>/<thread>),
# built the same way the bot does. `jump_url` is null when the guild id isn't
# configured (DISCORD_RPGCLUB_GUILD_ID).
#
# The columns already carry the useful thread metadata: `thread_name` (title),
# `forum_channel_id`, `is_archived`, `last_seen_at`, and the bot's derived
# `gamedb_game_id`.
class ThreadResource
  include BaseResource

  columns_of DiscordThread

  attribute :jump_url do |thread|
    guild_id = ENV["DISCORD_RPGCLUB_GUILD_ID"].presence
    "https://discord.com/channels/#{guild_id}/#{thread.thread_id}" if guild_id
  end
end

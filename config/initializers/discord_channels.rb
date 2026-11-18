# frozen_string_literal: true

# Discord channel snowflake IDs for TheRPGClub guild.
# Channel IDs aren't secret; commit them so all environments stay aligned.
# To find a channel's ID: enable Discord Developer Mode, then right-click the
# channel in the channel list and choose "Copy Channel ID".
module DiscordChannels
  # The general chat channel, where the bot posts the Birthday Post
  # (Birthdays::PostJob).
  GENERAL = "191941851757019136"
end

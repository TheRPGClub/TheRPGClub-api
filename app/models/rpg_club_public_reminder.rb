# frozen_string_literal: true

class RpgClubPublicReminder < ApplicationRecord
  self.table_name = "rpg_club_public_reminders"
  self.primary_key = "reminder_id"

  # The website may only pick a channel the bot has synced as text or
  # announcement (#320). Checked on create and when the channel changes, so a
  # stored reminder whose channel the bot has not synced (or has since
  # deleted) can still be edited or fired. The bot's own /publicreminder may
  # target any channel, threads included (threads are never synced), so the
  # controller sets `skip_channel_check` for service requests.
  attr_accessor :skip_channel_check

  validate :channel_is_synced_text_channel,
    if: -> { !skip_channel_check && (new_record? || will_save_change_to_channel_id?) }

  private

  def channel_is_synced_text_channel
    return if GuildChannel.text_channel?(channel_id)

    errors.add(:channel_id, "must be a synced text channel")
  end
end

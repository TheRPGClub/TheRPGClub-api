# frozen_string_literal: true

class RpgClubPublicReminder < ApplicationRecord
  self.table_name = "rpg_club_public_reminders"
  self.primary_key = "reminder_id"

  # The bot can only post to a channel it has synced as text or announcement
  # (#320). Checked on create and when the channel changes, so a stored
  # reminder whose channel the bot has not synced (or has since deleted) can
  # still be edited or fired.
  validate :channel_is_synced_text_channel, if: -> { new_record? || will_save_change_to_channel_id? }

  private

  def channel_is_synced_text_channel
    return if GuildChannel.text_channel?(channel_id)

    errors.add(:channel_id, "must be a synced text channel")
  end
end

# frozen_string_literal: true

# A per-user, per-channel message count the bot maintains by scanning channel
# history (bot parity, #47). Read-only over the API: the bot owns every write
# (incrementing the count and stamping `last_scanned_at`). The composite
# primary key `(user_id, channel_id)` mirrors the table.
class RpgClubUserChannelCount < ApplicationRecord
  self.table_name = "rpg_club_user_channel_counts"
  self.primary_key = %i[user_id channel_id]

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :channel_counts
end

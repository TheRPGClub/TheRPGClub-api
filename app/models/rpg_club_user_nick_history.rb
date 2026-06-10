# frozen_string_literal: true

# A nickname-change event the bot recorded for a user (bot parity, #49).
# Read-only over the API: the bot's member domain owns every write. Mirrors
# RpgClubUserAvatarHistory.
class RpgClubUserNickHistory < ApplicationRecord
  self.table_name = "rpg_club_user_nick_history"
  self.primary_key = "event_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :nick_history
end

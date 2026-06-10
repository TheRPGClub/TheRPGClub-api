# frozen_string_literal: true

# A per-user activity icon the bot captured from Discord rich presence (bot
# parity, #46). Read-only over the API: the bot's presence loop owns every
# write (first/last-seen tracking and `seen_count` increments).
class RpgClubUserActivityIcon < ApplicationRecord
  self.table_name = "rpg_club_user_activity_icons"
  self.primary_key = "id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :activity_icons
end

# frozen_string_literal: true

# One row per bot presence change (bot parity, #94). The Discord bot records
# each `/setpresence` activity here and reads back the latest/recent activity
# as it migrates `BotPresenceHistory` off direct SQL (RPGClub_GameDB#795).
#
# `id` is the surrogate primary key; `set_at` defaults to now() in the DB. Both
# are server-managed and never exposed (see BotPresenceResource) or written.
#
# A staff write (the site, save!(context: :staff)) is also held to Discord's
# activity name limit; the bot's own writes keep the column's.
class BotPresenceHistory < ApplicationRecord
  self.table_name = "bot_presence_history"

  # Discord's limit on an activity name.
  STAFF_NAME_MAX = 128

  normalizes :activity_name, with: ->(name) { name.strip }

  validates :activity_name, presence: true
  validates :activity_name, length: { maximum: STAFF_NAME_MAX }, on: :staff
end

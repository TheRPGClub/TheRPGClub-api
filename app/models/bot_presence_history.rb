# frozen_string_literal: true

# One row per bot presence change (bot parity, #94). The Discord bot records
# each `/setpresence` activity here and reads back the latest/recent activity
# as it migrates `BotPresenceHistory` off direct SQL (RPGClub_GameDB#795).
#
# `id` is the surrogate primary key; `set_at` defaults to now() in the DB. Both
# are server-managed and never exposed (see BotPresenceResource) or written.
class BotPresenceHistory < ApplicationRecord
  self.table_name = "bot_presence_history"
end

# frozen_string_literal: true

# Cache of Steam app -> GameDB game mappings (#166), persisted across imports
# so a repeated Steam app doesn't need to be re-resolved by the bot's
# matcher.
class RpgClubSteamAppGamedbMap < ApplicationRecord
  self.table_name = "rpg_club_steam_app_gamedb_map"
  self.primary_key = "map_id"

  STATUSES = %w[mapped skipped].freeze

  validates :steam_app_id, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :steam_app_id, uniqueness: true
end

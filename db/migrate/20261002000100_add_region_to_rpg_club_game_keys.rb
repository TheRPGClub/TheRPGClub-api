# frozen_string_literal: true

# The region a donated key redeems in (#262), so members don't claim a key
# their store will reject. Not nullable: every key has a region, defaulting to
# `Global` — existing rows are backfilled to it by the column default, and a
# donation that omits the region gets it too. The check constraint mirrors
# RpgClubGameKey::REGIONS.
class AddRegionToRpgClubGameKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_game_keys, :region, :string, limit: 20, null: false, default: "Global"
    add_check_constraint :rpg_club_game_keys,
      "region IN ('Global', 'NA', 'EU', 'UK', 'RU/CIS', 'Asia', 'Unknown')",
      name: "ck_rpg_club_game_keys_region"
  end
end

# frozen_string_literal: true

# A user's in-progress Steam collection import job (#166), backing the
# Discord bot's `/collection steam-import` command as it migrates off direct
# SQL (`rpg_club_steam_collection_imports`, steamCollectionImport.sql.ts)
# onto the API. `current_index`/`total_count` let the bot resume a paused or
# restart-interrupted import; the per-app work lives in `items`. `test_mode`
# marks a dry-run session: writes scoped to it are rolled back instead of
# persisted (see TestModeRollback).
class RpgClubSteamCollectionImport < ApplicationRecord
  self.table_name = "rpg_club_steam_collection_imports"
  self.primary_key = "import_id"

  STATUSES = %w[active paused completed canceled].freeze

  has_many :items,
    class_name: "RpgClubSteamCollectionImportItem",
    foreign_key: :import_id,
    dependent: :destroy,
    inverse_of: :import

  validates :user_id, :status, :steam_id64, presence: true
  validates :status, inclusion: { in: STATUSES }
end

# frozen_string_literal: true

# A single Steam app within a RpgClubSteamCollectionImport (#166). Carries
# the raw per-platform playtime pulled from the Steam API alongside the
# resolved match once the bot's matcher has run (`gamedb_game_id`,
# `collection_entry_id`, `match_confidence`/`match_candidate_json`), and the
# outcome (`status`/`result_reason`/`error_text`).
class RpgClubSteamCollectionImportItem < ApplicationRecord
  self.table_name = "rpg_club_steam_collection_import_items"
  self.primary_key = "item_id"

  STATUSES = %w[pending added updated skipped failed].freeze
  MATCH_CONFIDENCES = %w[exact fuzzy manual].freeze
  RESULT_REASONS = %w[auto_match manual_remap duplicate manual_skip skip_mapped
                       no_candidate invalid_remap platform_unresolved add_failed].freeze

  belongs_to :import,
    class_name: "RpgClubSteamCollectionImport",
    foreign_key: :import_id,
    primary_key: :import_id,
    inverse_of: :items

  validates :import_id, :row_index, :steam_app_id, :steam_app_name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :match_confidence, inclusion: { in: MATCH_CONFIDENCES }, allow_nil: true
  validates :result_reason, inclusion: { in: RESULT_REASONS }, allow_nil: true
  validates :row_index, uniqueness: { scope: :import_id }
end

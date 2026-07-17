# frozen_string_literal: true

# A single CSV row within a RpgClubCollectionCsvImport (#163). Carries the raw
# parsed CSV values (`raw_*`) alongside the resolved match once the bot's
# matcher has run (`platform_id`, `gamedb_game_id`, `collection_entry_id`,
# `match_confidence`/`match_candidate_json`), and the outcome
# (`status`/`result_reason`/`error_text`).
class RpgClubCollectionCsvImportItem < ApplicationRecord
  self.table_name = "rpg_club_collection_csv_import_items"
  self.primary_key = "item_id"

  STATUSES = %w[pending added updated skipped failed].freeze

  belongs_to :import,
    class_name: "RpgClubCollectionCsvImport",
    foreign_key: :import_id,
    primary_key: :import_id,
    inverse_of: :items

  validates :import_id, :row_index, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :row_index, uniqueness: { scope: :import_id }
end

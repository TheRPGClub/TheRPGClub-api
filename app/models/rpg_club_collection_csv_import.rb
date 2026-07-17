# frozen_string_literal: true

# A user's in-progress CSV collection import job (#163), backing the Discord
# bot's `/collection collection-csv-import` command as it migrates off direct
# SQL (`rpg_club_collection_csv_imports`, collectionCsvImport.sql.ts) onto the
# API. `current_index`/`total_count` let the bot resume a paused or
# restart-interrupted import; the per-row work lives in `items`.
class RpgClubCollectionCsvImport < ApplicationRecord
  self.table_name = "rpg_club_collection_csv_imports"
  self.primary_key = "import_id"

  STATUSES = %w[active paused completed canceled].freeze

  has_many :items,
    class_name: "RpgClubCollectionCsvImportItem",
    foreign_key: :import_id,
    dependent: :destroy,
    inverse_of: :import

  validates :user_id, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
end

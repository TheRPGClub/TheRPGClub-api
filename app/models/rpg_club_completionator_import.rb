# frozen_string_literal: true

# A user's in-progress Completionator import job (#164), backing the Discord
# bot's `/game-completion import-completionator` command as it migrates off
# direct SQL (`rpg_club_completionator_imports`, completionatorImport.sql.ts)
# onto the API. `current_index`/`total_count` let the bot resume a paused or
# restart-interrupted import; the per-row work lives in `items`.
class RpgClubCompletionatorImport < ApplicationRecord
  self.table_name = "rpg_club_completionator_imports"
  self.primary_key = "import_id"

  STATUSES = %w[active paused completed canceled].freeze

  has_many :items,
    class_name: "RpgClubCompletionatorImportItem",
    foreign_key: :import_id,
    dependent: :destroy,
    inverse_of: :import

  validates :user_id, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
end
